module Invidious::Channels::Livestreams
  extend self

  CACHE = {} of String => Tuple(Time, Set(String))
  WATCH_CACHE = {} of {String, String} => Tuple(Time, Bool?)

  MAX_WATCH_LOOKUPS = 3

  # A scheduled livestream can be in RSS before it appears in the Streams tab.
  # Cache unresolved lookups too, so transient upstream failures can be retried
  # without requesting the same page on every refresh.
  def probe_watch_page(id : String, ucid : String, &) : Bool?
    key = {id, ucid}
    if cached = WATCH_CACHE[key]?
      return cached[1] if cached[0] > Time.utc
    end
    return unless validate_video_id(id) && yield

    classification = fetch_watch_classification(id, ucid)
    WATCH_CACHE.delete(WATCH_CACHE.keys.first) if WATCH_CACHE.size >= 1024 && !WATCH_CACHE.has_key?(key)
    cooldown = classification.nil? ? Math.max(15.minutes, CONFIG.channel_refresh_interval * 6) : 15.minutes
    WATCH_CACHE[key] = {Time.utc + cooldown, classification}
    classification
  end

  private def fetch_watch_classification(id : String, ucid : String) : Bool?
    response = YT_POOL.client &.get("/watch?v=#{id}")
    return unless response.status_code == 200

    parse_watch_classification(response.body, id, ucid)
  rescue ex
    LOGGER.debug("Livestreams: unable to classify watch page #{id}: #{ex.message}")
    nil
  end

  private def parse_watch_classification(body : String, id : String, ucid : String) : Bool?
    match = body.match(/(?:window\["ytInitialPlayerResponse"\]|var\s+ytInitialPlayerResponse)\s*=\s*(\{.*?\});\s*<\/script>/m)
    return unless match

    player = JSON.parse(match[1])
    details = player["videoDetails"]?
    return unless details && details["videoId"]? == id && details["channelId"]? == ucid

    live_content = details["isLiveContent"]?.try(&.as_bool?)
    playability = player["playabilityStatus"]?
    status = playability.try(&.["status"]?)
    return false if status == "OK" && live_content == false

    # YouTube also sets isLiveContent on premieres. Require the offline
    # livestream slate and zero duration rather than the date or live flag alone.
    return unless live_content == true && details["isUpcoming"]? == true && details["lengthSeconds"]? == "0"
    return if details["isPremiere"]? == true || playability.try(&.["isPremiere"]?) == true

    slate = playability.try &.dig?("liveStreamability", "liveStreamabilityRenderer", "offlineSlate", "liveStreamOfflineSlateRenderer")
    true if status == "LIVE_STREAM_OFFLINE" && slate
  end

  def classify_video(id : String, author : String, ucid : String) : Bool?
    cached = CACHE[ucid]?
    if !cached || cached[0] <= Time.utc
      items, _ = fetch_page(author, ucid)
      cached = cache(ucid, items.map(&.id).to_set)
    end
    cached[1].includes?(id) ? true : nil
  rescue ex
    LOGGER.debug("Livestreams: unable to classify #{id}: #{ex.message}")
    nil
  end

  # Scan the latest streams and at most one older page on every channel refresh.
  def refresh(channel : InvidiousChannel) : Tuple(Hash(String, SearchVideo), String?)
    cursor = Invidious::Database::Channels.select(channel.id).try &.livestreams_continuation
    latest = {} of String => SearchVideo
    items, continuation = fetch_page(channel.author, channel.id)
    items.each { |video| latest[video.id] = video }
    cache(channel.id, latest.keys.to_set)
    Invidious::Database::ChannelVideos.classify_livestreams(channel.id, latest.keys)
    Invidious::Database::ChannelVideos.classify_membership(channel.id, items)

    if cursor.nil?
      cursor = continuation || ""
    elsif !cursor.empty?
      older, next_cursor = fetch_page(channel.author, channel.id, cursor)
      Invidious::Database::ChannelVideos.classify_livestreams(channel.id, older.map(&.id))
      Invidious::Database::ChannelVideos.classify_membership(channel.id, older)
      cursor = next_cursor || ""
    end

    {latest, cursor}
  rescue ex
    LOGGER.debug("Livestreams: unable to refresh #{channel.id}: #{ex.message}")
    {latest || {} of String => SearchVideo, cursor}
  end

  private def cache(ucid : String, ids : Set(String))
    CACHE.delete(CACHE.keys.first) if CACHE.size >= 256 && !CACHE.has_key?(ucid)
    CACHE[ucid] = {Time.utc + 5.minutes, ids}
  end

  private def fetch_page(author : String, ucid : String, cursor : String? = nil)
    items, continuation = Invidious::Channel::Tabs.get_livestreams(author, ucid, continuation: cursor)
    if items.any?(ProblematicTimelineItem)
      raise InfoException.new("Unable to parse channel livestreams")
    end
    {items.select(SearchVideo), continuation}
  end

  # YouTube's RSS can omit upcoming and active broadcasts.
  def add_missing(channel : InvidiousChannel, streams : Hash(String, SearchVideo), rss_ids : Set(String))
    now = Time.utc
    streams.each do |id, stream|
      next if rss_ids.includes?(id)

      live_now = stream.badges.live_now?
      scheduled_at = stream.premiere_timestamp.try { |time| time if time > now }
      if live_now || scheduled_at
        video = ChannelVideo.new({
          id:                 id,
          title:              stream.title,
          published:          now,
          updated:            now,
          ucid:               channel.id,
          author:             channel.author,
          length_seconds:     stream.length_seconds,
          live_now:           live_now,
          premiere_timestamp: scheduled_at,
          views:              stream.views,
          is_short:           nil,
          is_livestream:      true,
          is_members_only:    stream.is_members_only,
        })
        if Invidious::Database::ChannelVideos.insert_livestream_from_tab(video)
          NOTIFICATION_CHANNEL.send(VideoNotification.from_video(video))
          next
        end
      end

      Invidious::Database::ChannelVideos.update_livestream_status(channel.id, id, live_now, scheduled_at)
    end
  end
end
