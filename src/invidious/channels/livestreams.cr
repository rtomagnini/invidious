module Invidious::Channels::Livestreams
  extend self

  CACHE = {} of String => Tuple(Time, Set(String))
  WATCH_CACHE = {} of {String, String} => Tuple(Time, Bool?)

  MAX_WATCH_LOOKUPS = 3
  WATCH_RETRY_DELAY = 5.minutes

  # Check unseen candidates first, then retry the ones checked least recently.
  def classify_rss_candidates(ids : Array(String), ucid : String) : Hash(String, Bool)
    ordered = ids.uniq.sort_by { |id| WATCH_CACHE[{id, ucid}]?.try(&.first) || Time.unix(0) }
    classifications = {} of String => Bool
    remaining = MAX_WATCH_LOOKUPS

    ordered.each do |id|
      result = probe_watch_page(id, ucid) do
        next false if remaining <= 0
        remaining -= 1
        true
      end
      classifications[id] = result unless result.nil?
    end
    classifications
  end

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
    cooldown = classification.nil? ? WATCH_RETRY_DELAY : 15.minutes
    WATCH_CACHE[key] = {Time.utc + cooldown, classification}
    LOGGER.info("Livestreams: classified scheduled RSS video #{id} (#{ucid})") if classification == true
    classification
  end

  private def fetch_watch_classification(id : String, ucid : String) : Bool?
    result = classify_from_watch_page(id, ucid)
    return result unless result.nil?

    if player = YoutubeAPI.player(video_id: id)
      result = classify_player(JSON::Any.new(player), id, ucid)
      LOGGER.debug("Livestreams: player fallback unresolved for #{id}") if result.nil?
    end
    result
  rescue ex
    LOGGER.debug("Livestreams: player lookup failed for #{id}: #{ex.message}")
    nil
  end

  private def classify_from_watch_page(id : String, ucid : String) : Bool?
    response = YT_POOL.client &.get("/watch?v=#{id}")
    unless response.status_code == 200
      LOGGER.debug("Livestreams: watch page returned HTTP #{response.status_code} for #{id}")
      return
    end

    player = extract_watch_player(response.body)
    unless player
      LOGGER.debug("Livestreams: watch page player data missing for #{id}")
      return
    end

    result = classify_player(player, id, ucid)
    LOGGER.debug("Livestreams: watch page player data unresolved for #{id}") if result.nil?
    result
  rescue ex
    LOGGER.debug("Livestreams: watch page lookup failed for #{id}: #{ex.message}")
    nil
  end

  # Only read the JSON object. YouTube can append other JavaScript before </script>.
  private def extract_watch_player(body : String) : JSON::Any?
    assignment = body.match(/(?:window\s*\[\s*["']ytInitialPlayerResponse["']\s*\]|\bytInitialPlayerResponse)\s*=\s*(?=\{)/)
    return unless assignment

    start = assignment.byte_end
    depth = 0
    in_string = false
    escaped = false

    body.to_slice[start..].each_with_index do |byte, index|
      if in_string
        if escaped
          escaped = false
        elsif byte == '\\'.ord
          escaped = true
        elsif byte == '"'.ord
          in_string = false
        end
      elsif byte == '"'.ord
        in_string = true
      elsif byte == '{'.ord
        depth += 1
      elsif byte == '}'.ord
        depth -= 1
        return JSON.parse(body.byte_slice(start, index + 1)) if depth == 0
      end
    end

    nil
  end

  private def classify_player(player : JSON::Any, id : String, ucid : String) : Bool?
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
