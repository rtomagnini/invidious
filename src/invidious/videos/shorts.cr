module Invidious::Videos::Shorts
  extend self

  # Only affirmative YouTube metadata identifies a Short. Missing metadata is
  # unknown; duration, aspect ratio and title are deliberately not considered.
  def from_renderer(data : JSON::Any) : Bool?
    return true if data["shortsLockupViewModel"]? || data["reelItemRenderer"]?
    return true if data.dig?("navigationEndpoint", "reelWatchEndpoint")
    return true if data.dig?("onTap", "innertubeCommand", "reelWatchEndpoint")

    url = data.dig?("navigationEndpoint", "commandMetadata", "webCommandMetadata", "url").try &.as_s?
    return true if url.try &.starts_with?("/shorts/")

    data["thumbnailOverlays"]?.try &.as_a.each do |overlay|
      status = overlay["thumbnailOverlayTimeStatusRenderer"]?
      next unless status
      return true if status["style"]?.try(&.as_s?) == "SHORTS"
      return true if status.dig?("icon", "iconType").try(&.as_s?) == "SHORTS"
      return true if status.dig?("text", "simpleText").try(&.as_s?) == "SHORTS"
    end
    nil
  end

  def filter(items : T, hide_shorts : Bool) : T forall T
    return items unless hide_shorts
    items.reject! do |item|
      if item.is_a?(Category)
        filter(item.contents, true)
        item.contents.empty?
      elsif item.responds_to?(:is_short)
        item.is_short == true
      else
        false
      end
    end
  end
end
