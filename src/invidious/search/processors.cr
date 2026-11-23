module Invidious::Search::Processors
  extend self

  # Regular search (`/search` endpoint)
  def regular(query : Query) : Array(SearchItem)
    search_params = query.filters.to_yt_params(page: query.page)

    client_config = YoutubeAPI::ClientConfig.new(region: query.region)
    initial_data = YoutubeAPI.search(query.text, search_params, client_config: client_config)

    items, _ = extract_items(initial_data)
    return items.reject!(Category)
  end

  # Search a youtube channel
  # TODO: clean code, and rely more on YoutubeAPI
  def channel(query : Query) : Array(SearchItem)
    response = YT_POOL.client &.get("/channel/#{query.channel}")

    if response.status_code == 404
      response = YT_POOL.client &.get("/user/#{query.channel}")
      response = YT_POOL.client &.get("/c/#{query.channel}") if response.status_code == 404
      initial_data = Invidious::Helpers.extract_initial_data(response.body)
      ucid = initial_data.dig?("header", "c4TabbedHeaderRenderer", "channelId").try(&.as_s?)
      raise ChannelSearchException.new(query.channel) if !ucid
    else
      ucid = query.channel
    end

    continuation = Invidious::Search::CToken.produce_channel_search_continuation(ucid, query.text, query.page)
    response_json = YoutubeAPI.browse(continuation)

    items, _ = extract_items(response_json, "", ucid)
    return items.reject!(Category)
  end

  # Search inside of user subscriptions
  def subscriptions(query : Query, user : Invidious::User) : Array(ChannelVideo)
    view_name = "subscriptions_#{sha256(user.email)}"
    filter = Invidious::Database::SubscriptionFilters.allowed_sql("$3", "$4")

    return PG_DB.query_all(<<-SQL, query.text, (query.page - 1) * 20, user.email, user.preferences.hide_shorts, as: ChannelVideo)
      SELECT cv.* FROM #{view_name} feed JOIN channel_videos cv ON cv.id = feed.id
      WHERE #{filter}
        AND (to_tsvector(cv.title) || to_tsvector(cv.author)) @@ plainto_tsquery($1)
      LIMIT 20 OFFSET $2
      SQL
  end
end
