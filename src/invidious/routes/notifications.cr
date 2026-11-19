module Invidious::Routes::Notifications
  def self.inbox(env)
    return Errors.error_json(403, "No such user") unless user = env.get?("user").try &.as(User)

    preferences = env.get("preferences").as(Preferences)
    locale = preferences.locale
    thin_mode = preferences.thin_mode
    notification_rows = Invidious::Database::Users.select_notification_inbox(user)
    notification_count = notification_rows.first?.try(&.[6]) || 0_i64

    env.response.content_type = "text/html; charset=utf-8"
    env.response.headers["Cache-Control"] = "no-store"
    env.response.headers["X-Notification-Count"] = notification_count.to_s
    rendered "components/notification_inbox"
  end

  def self.clear_inbox(env)
    user = env.get?("user").try &.as(User)
    sid = env.get?("sid").try &.as(String)
    return Errors.error_json(403, "No such user") unless user && sid

    locale = env.get("preferences").as(Preferences).locale
    begin
      token = env.params.body["csrf_token"]?
      Invidious::Helpers::Tokens.validate_request(token, sid, env.request, HMAC_KEY, locale)
    rescue ex
      return Errors.error_json(400, ex)
    end

    Invidious::Database::Users.clear_notifications(user)
    env.response.status_code = 204
    ""
  end

  # /modify_notifications
  # will "ding" all subscriptions.
  # /modify_notifications?receive_all_updates=false&receive_no_updates=false
  # will "unding" all subscriptions.
  def self.modify(env)
    locale = env.get("preferences").as(Preferences).locale

    user = env.get? "user"
    sid = env.get? "sid"
    referer = get_referer(env, "/")

    redirect = env.params.query["redirect"]?
    redirect ||= "false"
    redirect = redirect == "true"

    if !user
      if redirect
        return env.redirect referer
      else
        return Errors.error_json(403, "No such user")
      end
    end

    user = user.as(User)

    if redirect
      env.redirect referer
    else
      env.response.content_type = "application/json"
      "{}"
    end
  end
end
