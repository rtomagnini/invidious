module Invidious::Channels::Livestreams
  extend self

  CACHE = {} of String => Tuple(Time, Set(String))

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

    if cursor.nil?
      cursor = continuation || ""
    elsif !cursor.empty?
      older, next_cursor = fetch_page(channel.author, channel.id, cursor)
      Invidious::Database::ChannelVideos.classify_livestreams(channel.id, older.map(&.id))
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
