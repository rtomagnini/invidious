struct MixVideo
  include DB::Serializable

  property title : String
  property id : String
  property author : String
  property ucid : String
  property length_seconds : Int32
  property index : Int32
  property rdid : String
end

struct Mix
  include DB::Serializable

  property title : String
  property id : String
  property videos : Array(MixVideo)
end

def fetch_mix(rdid, video_id, cookies = nil, locale = nil)
  headers = HTTP::Headers.new

  if cookies
    headers = cookies.add_request_headers(headers)
  end

  video_id = "CvFH_6DNRCY" if rdid.starts_with? "OLAK5uy_"
  response = YT_POOL.client &.get("/watch?v=#{video_id}&list=#{rdid}&gl=US&hl=en", headers)
  initial_data = Invidious::Helpers.extract_initial_data(response.body)

  if !initial_data["contents"]["twoColumnWatchNextResults"]["playlist"]?
    raise InfoException.new("Could not create mix.")
  end

  playlist = initial_data["contents"]["twoColumnWatchNextResults"]["playlist"]["playlist"]
  mix_title = playlist["title"].as_s

  contents = playlist["contents"].as_a
  if contents.map { |video| video["playlistPanelVideoRenderer"]["videoId"] }.includes? video_id
    until contents[0]["playlistPanelVideoRenderer"]["videoId"].as_s == video_id
      contents.shift
    end
  end

  videos = [] of MixVideo
  contents.each do |item|
    item = item["playlistPanelVideoRenderer"]

    id = item["videoId"].as_s
    title = item["title"]?.try &.["simpleText"].as_s
    next if !title

    author = item.dig?("longBylineText", "runs", 0, "text").try &.as_s || ""
    ucid = item.dig?("longBylineText", "runs", 0, "navigationEndpoint", "browseEndpoint", "browseId").try &.as_s || ""
    length_text = item.dig?("lengthText", "simpleText").try &.as_s
    length_seconds = length_text ? decode_length_seconds(length_text) : 0
    index = item.dig?("navigationEndpoint", "watchEndpoint", "index").try &.as_i || videos.size

    videos << MixVideo.new({
      title:          title,
      id:             id,
      author:         author,
      ucid:           ucid,
      length_seconds: length_seconds,
      index:          index,
      rdid:           rdid,
    })
  end

  if !cookies && !videos.empty?
    next_page = fetch_mix(rdid, videos[-1].id, response.cookies, locale)
    videos += next_page.videos
  end

  videos.uniq!(&.id)
  videos = videos.first(50)
  return Mix.new({
    title:  mix_title,
    id:     rdid,
    videos: videos,
  })
end

def template_mix_queue(mix : Mix, current_id : String, locale : String, listen : Bool = false, thin_mode : Bool = false, scrollable : Bool = false)
  mix_id = URI.encode_www_form(mix.id)

  String.build do |html|
    html << %(<ol class="mix-queue#{" mix-queue-scroll" if scrollable}">)
    mix.videos.each do |video|
      video_id = URI.encode_www_form(video.id)
      current = video.id == current_id
      duration = recode_length_seconds(video.length_seconds) if video.length_seconds > 0
      html << <<-END_HTML
        <li class="mix-queue-item" id="#{video_id}">
          <a href="/watch?v=#{video_id}&amp;list=#{mix_id}#{"&amp;listen=1" if listen}"#{" aria-current=\"true\"" if current}>
        END_HTML
      unless thin_mode
        html << <<-END_HTML
          <span class="mix-thumb">
            <img loading="lazy" src="/vi/#{video_id}/mqdefault.jpg" alt="" width="320" height="180">
            #{"<span class=\"mix-duration\">#{duration}</span>" if duration}
          </span>
          END_HTML
      end
      html << <<-END_HTML
          <span class="mix-video-info" dir="auto">
            <strong>#{HTML.escape(video.title)}</strong>
            <span class="mix-video-meta">#{HTML.escape(video.author)}#{" · #{duration}" if thin_mode && duration}</span>
            #{"<span class=\"mix-video-meta\"><i class=\"icon ion-ios-play mix-current-icon\" aria-hidden=\"true\"></i> #{I18n.translate(locale, "mix_current")}</span>" if current}
          </span>
        </a>
      </li>
      END_HTML
    end
    html << "</ol>"
  end
end
