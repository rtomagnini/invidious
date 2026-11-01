module Invidious::Channels::Shorts
  extend self

  # Shared by PubSub deliveries from the same channel. Bound both age and size.
  CACHE = {} of String => Tuple(Time, Set(String))

  def latest(author : String, ucid : String) : Set(String)
    if cached = CACHE[ucid]?
      return cached[1] if Time.utc < cached[0]
    end

    items, _ = Invidious::Channel::Tabs.get_shorts(author, ucid)
    ids = items.select(SearchVideo).map(&.id).to_set
    CACHE.delete(CACHE.keys.first) if CACHE.size >= 256
    CACHE[ucid] = {Time.utc + 5.minutes, ids}
    ids
  end

  def classify_video(id : String, author : String, ucid : String) : Bool?
    stored = Invidious::Database::ChannelVideos.select([id]).first?
    return stored.is_short if stored && !stored.is_short.nil?

    latest(author, ucid).includes?(id) ? true : nil
  rescue ex
    LOGGER.debug("Shorts: unable to classify #{id}: #{ex.message}")
    nil
  end

  # Always refresh the newest page, then advance at most one historical page.
  # Persisting the cursor allows existing subscriptions to be classified gradually.
  def refresh(channel : InvidiousChannel) : Tuple(Set(String), String?)
    cursor = Invidious::Database::Channels.select(channel.id).try &.shorts_continuation
    items, next_continuation = Invidious::Channel::Tabs.get_shorts(channel.author, channel.id)
    if items.any?(ProblematicTimelineItem)
      raise InfoException.new("Unable to parse channel Shorts")
    end
    ids = items.select(SearchVideo).map(&.id).to_set
    CACHE.delete(CACHE.keys.first) if CACHE.size >= 256
    CACHE[channel.id] = {Time.utc + 5.minutes, ids}
    Invidious::Database::ChannelVideos.classify(channel.id, ids.to_a, true)

    if cursor.nil?
      cursor = next_continuation || ""
    elsif !cursor.empty?
      older, next_cursor = Invidious::Channel::Tabs.get_shorts(channel.author, channel.id, continuation: cursor)
      if older.any?(ProblematicTimelineItem)
        raise InfoException.new("Unable to parse historical Shorts")
      end
      Invidious::Database::ChannelVideos.classify(channel.id, older.select(SearchVideo).map(&.id), true)
      cursor = next_cursor || ""
    end

    {ids, cursor}
  rescue ex
    # A Shorts failure must not interrupt normal subscription updates or turn
    # unclassified uploads into regular videos. Retry the cursor next refresh.
    LOGGER.debug("Shorts: unable to refresh #{channel.id}: #{ex.message}")
    {Set(String).new, cursor}
  end
end
