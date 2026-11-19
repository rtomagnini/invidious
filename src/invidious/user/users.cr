require "crypto/bcrypt/password"

module Invidious::User::Users
  extend self
  # Materialized views may not be defined using bound parameters (`$1` as used elsewhere)
  MATERIALIZED_VIEW_SQL = ->(email : String) { "SELECT cv.* FROM channel_videos cv WHERE EXISTS (SELECT subscriptions FROM users u WHERE cv.ucid = ANY (u.subscriptions) AND u.email = E'#{email.gsub({'\'' => "\\'", '\\' => "\\\\"})}') ORDER BY published DESC" }

  def create_user(sid, email, password)
    password = Crypto::Bcrypt::Password.create(password, cost: 10)
    token = Base64.urlsafe_encode(Random::Secure.random_bytes(32))

    user = Invidious::User.new({
      updated:           Time.utc,
      notifications:     [] of String,
      subscriptions:     [] of String,
      email:             email,
      preferences:       Preferences.new(CONFIG.default_user_preferences.to_tuple),
      password:          password.to_s,
      token:             token,
      watched:           [] of String,
      feed_needs_update: true,
    })

    return user, sid
  end

  def get_subscription_feed(user, max_results = 40, page = 1)
    limit = max_results.clamp(0, MAX_ITEMS_PER_PAGE)
    offset = (page - 1) * limit

    notifications = Invidious::Database::Users.select_notifications(user)
    view_name = "subscriptions_#{sha256(user.email)}"
    filter = Invidious::Database::SubscriptionFilters.allowed_sql("$1", "$2")

    if user.preferences.notifications_only && !notifications.empty?
      # Only show notifications
      notifications = PG_DB.query_all(<<-SQL, user.email, user.preferences.hide_shorts, notifications, as: ChannelVideo)
        SELECT cv.* FROM channel_videos cv WHERE cv.id = ANY($3) AND #{filter}
        SQL
      videos = [] of ChannelVideo

      notifications.sort_by!(&.published).reverse!

      case user.preferences.sort
      when "alphabetically"
        notifications.sort_by!(&.title)
      when "alphabetically - reverse"
        notifications.sort_by!(&.title).reverse!
      when "channel name"
        notifications.sort_by!(&.author)
      when "channel name - reverse"
        notifications.sort_by!(&.author).reverse!
      end
    else
      where = "#{filter} AND (NOT $3 OR NOT cv.id = ANY($4::text[]))"
      args = {user.email, user.preferences.hide_shorts, user.preferences.unseen_only, user.watched}

      if user.preferences.latest_only
        videos = PG_DB.query_all(<<-SQL, *args, as: ChannelVideo)
          SELECT DISTINCT ON (cv.ucid) cv.* FROM #{view_name} cv
          WHERE #{where} ORDER BY cv.ucid, cv.published DESC
          SQL
        videos.sort_by!(&.published).reverse!
      else
        videos = PG_DB.query_all(<<-SQL, *args, limit, offset, as: ChannelVideo)
          SELECT cv.* FROM #{view_name} cv WHERE #{where}
          ORDER BY cv.published DESC LIMIT $5 OFFSET $6
          SQL
      end

      case user.preferences.sort
      when "published - reverse"
        videos.sort_by!(&.published)
      when "alphabetically"
        videos.sort_by!(&.title)
      when "alphabetically - reverse"
        videos.sort_by!(&.title).reverse!
      when "channel name"
        videos.sort_by!(&.author)
      when "channel name - reverse"
        videos.sort_by!(&.author).reverse!
      end

      notifications = Invidious::Database::Users.select_notifications(user)
      notifications = videos.select { |v| notifications.includes? v.id }
      videos = videos - notifications
    end

    return videos, notifications
  end
end
