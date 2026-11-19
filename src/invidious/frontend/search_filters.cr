module Invidious::Frontend::SearchFilters
  extend self

  def generate(filters : Search::Filters, query : String, locale : String, search_privacy : Bool) : String
    String.build(8000) do |str|
      method = search_privacy ? "post" : "get"
      str << %(<form class="search-filter-form" action="/search" method="#{method}">)
      str << %(<input type="hidden" name="q" value=") << HTML.escape(query) << %(">)
      str << %(<div class="search-filter-grid">)

      filter_wrapper(date)
      filter_wrapper(type)
      filter_wrapper(duration)
      filter_wrapper(features)
      filter_wrapper(sort)

      str << %(</div><div class="search-filter-apply"><button type="submit">)
      str << I18n.translate(locale, "search_filters_apply_button")
      str << %(</button></div></form>)
    end
  end

  # Generate wrapper HTML (`<div>`, filter name, etc...) around the
  # `<input>` elements of a search filter
  macro filter_wrapper(name)
    str << %(<fieldset class="search-filter-group">)

    str << "<legend>"
    str << I18n.translate(locale, "search_filters_{{ name }}_label")
    str << "</legend>"

    str << %(<div class="search-filter-options">)
    make_{{ name }}_filter_options(str, filters.{{ name }}, locale)
    str << "</div></fieldset>"
  end

  # Generates the HTML for the list of radio buttons of the "date" search filter
  def make_date_filter_options(str : String::Builder, value : Search::Filters::Date, locale : String)
    {% for value in Invidious::Search::Filters::Date.constants %}
      {% date = value.underscore %}

      str << "\t\t\t\t\t\t<div>"
      str << "<input type='radio' name='date' id='filter-date-{{ date }}' value='{{ date }}'"
      str << " checked" if value.{{ date }}?
      str << '>'

      str << "<label for='filter-date-{{ date }}'>"
      str << I18n.translate(locale, "search_filters_date_option_{{ date }}")
      str << "</label></div>\n"
    {% end %}
  end

  # Generates the HTML for the list of radio buttons of the "type" search filter
  def make_type_filter_options(str : String::Builder, value : Search::Filters::Type, locale : String)
    {% for value in Invidious::Search::Filters::Type.constants %}
      {% type = value.underscore %}

      str << "\t\t\t\t\t\t<div>"
      str << "<input type='radio' name='type' id='filter-type-{{ type }}' value='{{ type }}'"
      str << " checked" if value.{{ type }}?
      str << '>'

      str << "<label for='filter-type-{{ type }}'>"
      str << I18n.translate(locale, "search_filters_type_option_{{ type }}")
      str << "</label></div>\n"
    {% end %}
  end

  # Generates the HTML for the list of radio buttons of the "duration" search filter
  def make_duration_filter_options(str : String::Builder, value : Search::Filters::Duration, locale : String)
    {% for value in Invidious::Search::Filters::Duration.constants %}
      {% duration = value.underscore %}

      str << "\t\t\t\t\t\t<div>"
      str << "<input type='radio' name='duration' id='filter-duration-{{ duration }}' value='{{ duration }}'"
      str << " checked" if value.{{ duration }}?
      str << '>'

      str << "<label for='filter-duration-{{ duration }}'>"
      str << I18n.translate(locale, "search_filters_duration_option_{{ duration }}")
      str << "</label></div>\n"
    {% end %}
  end

  # Generates the HTML for the list of checkboxes of the "features" search filter
  def make_features_filter_options(str : String::Builder, value : Search::Filters::Features, locale : String)
    {% for value in Invidious::Search::Filters::Features.constants %}
      {% if value.stringify != "All" && value.stringify != "None" %}
        {% feature = value.underscore %}

        str << "\t\t\t\t\t\t<div>"
        str << "<input type='checkbox' name='features' id='filter-feature-{{ feature }}' value='{{ feature }}'"
        str << " checked" if value.{{ feature }}?
        str << '>'

        str << "<label for='filter-feature-{{ feature }}'>"
        str << I18n.translate(locale, "search_filters_features_option_{{ feature }}")
        str << "</label></div>\n"
      {% end %}
    {% end %}
  end

  # Generates the HTML for the list of radio buttons of the "sort" search filter
  def make_sort_filter_options(str : String::Builder, value : Search::Filters::Sort, locale : String)
    {% for value in Invidious::Search::Filters::Sort.constants %}
      {% sort = value.underscore %}

      str << "\t\t\t\t\t\t<div>"
      str << "<input type='radio' name='sort' id='filter-sort-{{ sort }}' value='{{ sort }}'"
      str << " checked" if value.{{ sort }}?
      str << '>'

      str << "<label for='filter-sort-{{ sort }}'>"
      str << I18n.translate(locale, "search_filters_sort_option_{{ sort }}")
      str << "</label></div>\n"
    {% end %}
  end
end
