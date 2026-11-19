module Invidious::Frontend::SearchFilters
  extend self

  def generate(filters : Search::Filters, locale : String) : String
    String.build(5000) do |str|
      str << %(<div class="search-filter-grid">)
      filter_select(date, Invidious::Search::Filters::Date)
      filter_select(duration, Invidious::Search::Filters::Duration)
      filter_select(sort, Invidious::Search::Filters::Sort)
      str << "</div>"

      str << "<details class=\"search-filter-advanced\""
      str << " open" if !filters.features.none? || filters.type.movie? || filters.type.show?
      str << "><summary>" << I18n.translate(locale, "search_filters_advanced")
      str << %( <i class="icon ion-ios-arrow-down search-filter-chevron" aria-hidden="true"></i></summary>)
      str << %(<div class="search-filter-advanced-body">)
      filter_select(type, Invidious::Search::Filters::Type)
      str << %(<fieldset class="search-feature-group"><legend>)
      str << I18n.translate(locale, "search_filters_features_label")
      str << %(</legend><div class="search-feature-options">)
      make_features_filter_options(str, filters.features, locale)
      str << "</div></fieldset></div></details>"
    end
  end

  macro filter_select(name, enum_type)
    str << %(<label class="search-filter-select"><span>)
    str << I18n.translate(locale, "search_filters_{{ name }}_label")
    str << %(</span><select name="{{ name }}">)
    {% for option in enum_type.resolve.constants %}
      {% key = option.underscore %}
      str << %(<option value="{{ key }}")
      str << " selected" if filters.{{ name }}.{{ key }}?
      str << ">" << I18n.translate(locale, "search_filters_{{ name }}_option_{{ key }}") << "</option>"
    {% end %}
    str << "</select></label>"
  end

  private def make_features_filter_options(str, features, locale)
    {% for option in Invidious::Search::Filters::Features.constants %}
      {% unless option.stringify == "All" || option.stringify == "None" %}
        {% key = option.underscore %}
        flag = Search::Filters::Features::{{ option }}
        value = Search::Filters.format_features(flag)
        str << %(<label><input type="checkbox" name="features" value=") << value << %(")
        str << " checked" if features.{{ key }}?
        str << %(><span>) << I18n.translate(locale, "search_filters_features_option_{{ key }}") << %(</span></label>)
      {% end %}
    {% end %}
  end
end
