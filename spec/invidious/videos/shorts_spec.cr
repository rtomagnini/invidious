require "../../parsers_helper.cr"

private def shorts_item(renderer : String) : SearchVideo
  item = parse_item(JSON.parse(renderer), "Example channel", "UCexample")
  item.as(SearchVideo)
end

Spectator.describe Invidious::Videos::Shorts do
  it "keeps a normal brief video with no Shorts metadata" do
    item = shorts_item(%({"videoRenderer":{"videoId":"normal","title":{"simpleText":"Brief video"},"lengthText":{"simpleText":"0:15"}}}))
    expect(item.is_short).to be_nil
    expect(Invidious::Videos::Shorts.filter([item], true).size).to eq(1)
  end

  it "recognizes a reel endpoint even when an explicit long duration is supplied" do
    item = shorts_item(%({"videoRenderer":{"videoId":"short","title":{"simpleText":"Example"},"lengthText":{"simpleText":"3:00"},"navigationEndpoint":{"reelWatchEndpoint":{"videoId":"short"}}}}))
    expect(item.is_short).to eq(true)
    expect(Invidious::Videos::Shorts.filter([item], true)).to be_empty
    expect(Invidious::Videos::Shorts.filter([item], false).size).to eq(1)
  end

  it "preserves classification from the modern Shorts renderer" do
    item = shorts_item(%({"richItemRenderer":{"content":{"shortsLockupViewModel":{"onTap":{"innertubeCommand":{"reelWatchEndpoint":{"videoId":"modern"}}},"overlayMetadata":{"primaryText":{"content":"Example"},"secondaryText":{"content":"123 views"}}}}}}))
    expect(item.id).to eq("modern")
    expect(item.is_short).to eq(true)
  end

  it "recognizes the Shorts thumbnail style without depending on translated text" do
    data = JSON.parse(%({"thumbnailOverlays":[{"thumbnailOverlayTimeStatusRenderer":{"style":"SHORTS","text":{"simpleText":"Cortos"}}}]}))
    expect(Invidious::Videos::Shorts.from_renderer(data)).to eq(true)
  end

  it "does not use hashtags or portrait thumbnails as classification" do
    data = JSON.parse(%({"title":{"simpleText":"#shorts"},"thumbnail":{"thumbnails":[{"width":100,"height":200}]}}))
    expect(Invidious::Videos::Shorts.from_renderer(data)).to be_nil
  end

  it "filters nested Shorts while retaining other category items" do
    normal = shorts_item(%({"videoRenderer":{"videoId":"normal","title":{"simpleText":"Brief"}}}))
    short = normal
    short.is_short = true
    category = Category.new({title: "Videos", contents: [normal, short] of SearchItem, url: nil, description_html: "", badges: nil})
    Invidious::Videos::Shorts.filter([category], true)
    expect(category.contents.size).to eq(1)
  end
end
