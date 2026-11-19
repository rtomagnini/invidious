module Invidious::Frontend::ChannelPage
  extend self

  enum TabsAvailable
    Videos
    Shorts
    Streams
    Podcasts
    Releases
    Courses
    Shows
    Playlists
    Posts
    Channels
  end

  def generate_tabs_links(locale : String, channel : AboutChannel, selected_tab : TabsAvailable)
    return String.build(1500) do |str|
      base_url = "/channel/#{channel.ucid}"

      TabsAvailable.each do |tab|
        # Ignore playlists, as it is not supported for auto-generated channels yet
        next if (tab.playlists? && channel.auto_generated)

        tab_name = tab.to_s.downcase

        next unless channel.tabs.includes? tab_name

        # Video tab doesn't have the last path component.
        url = tab.videos? ? base_url : "#{base_url}/#{tab_name}"
        str << %(<a href=") << url << %(")
        str << %( aria-current="page") if tab == selected_tab
        str << ">" << HTML.escape(I18n.translate(locale, "channel_tab_#{tab_name}_label")) << "</a>\n"
      end
    end
  end
end
