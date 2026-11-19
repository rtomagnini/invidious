# -------------------
#  Issue template
# -------------------

module Errors
  extend self

  macro error_template(*args)
    Errors.error_template_helper(env, {{ args.splat }})
  end

  def github_details(summary : String, content : String)
    details = %(\n<details>)
    details += %(\n<summary>#{summary}</summary>)
    details += %(\n<p>)
    details += %(\n   \n```\n)
    details += content.strip
    details += %(\n```)
    details += %(\n</p>)
    details += %(\n</details>)
    return HTML.escape(details)
  end

  def get_issue_template(env : HTTP::Server::Context, exception : Exception) : Tuple(String, String)
    issue_title = "#{exception.message} (#{exception.class})"

    issue_template = <<-TEXT
      Title: `#{HTML.escape(issue_title)}`
      Date: `#{Time::Format::ISO_8601_DATE_TIME.format(Time.utc)}`
      Route: `#{HTML.escape(env.request.resource)}`
      Version: `#{SOFTWARE["version"]} @ #{SOFTWARE["branch"]}`
      TEXT

    issue_template += github_details("Backtrace", exception.inspect_with_backtrace)

    return issue_title, issue_template
  end

  def error_template_helper(env : HTTP::Server::Context, status_code : Int32, exception : Exception)
    if exception.is_a?(InfoException)
      return error_template_helper(env, status_code, exception.message || "")
    end

    locale = env.get("preferences").as(Preferences).locale

    env.response.content_type = "text/html"
    env.response.status_code = status_code

    # Unpacking into issue_title, issue_template directly causes a compiler error
    # I have no idea why.
    issue_template_components = self.get_issue_template(env, exception)
    issue_title, issue_template = issue_template_components

    # URLs for the error message below
    url_faq = "https://github.com/iv-org/documentation/blob/master/docs/faq.md"
    url_search_issues = "https://github.com/iv-org/invidious/issues"
    url_search_issues += "?q=is:issue+is:open+"
    url_search_issues += URI.encode_www_form("[Bug] #{issue_title}")

    url_new_issue = "https://github.com/iv-org/invidious/issues/new"
    url_new_issue += "?labels=bug&template=bug_report.md&title="
    url_new_issue += URI.encode_www_form("[Bug] " + issue_title)

    error_title = I18n.translate(locale, "error_page_title")
    error_message = I18n.translate(locale, "crash_page_you_found_a_bug")
    next_steps = error_redirect_helper(env, retry_request: true)
    diagnostics = <<-END_HTML
      <ul>
        <li>#{I18n.translate(locale, "crash_page_read_the_faq", url_faq)}</li>
        <li>#{I18n.translate(locale, "crash_page_search_issue", HTML.escape(url_search_issues))}</li>
      </ul>
      <p>#{I18n.translate(locale, "crash_page_report_issue", HTML.escape(url_new_issue))}</p>
      <pre tabindex="0">#{issue_template}</pre>
      END_HTML

    return templated "error"
  end

  def error_template_helper(env : HTTP::Server::Context, status_code : Int32, message : String)
    env.response.content_type = "text/html"
    env.response.status_code = status_code

    locale = env.get("preferences").as(Preferences).locale

    error_title = I18n.translate(locale, status_code == 404 ? "error_not_found" : "error_page_title")
    error_message = I18n.translate(locale, message)
    next_steps = error_redirect_helper(env)
    diagnostics = nil

    return templated "error"
  end

  # -------------------
  #  Atom feeds
  # -------------------

  macro error_atom(*args)
    Errors.error_atom_helper(env, {{ args.splat }})
  end

  def error_atom_helper(env : HTTP::Server::Context, status_code : Int32, exception : Exception)
    if exception.is_a?(InfoException)
      return error_atom_helper(env, status_code, exception.message || "")
    end

    env.response.content_type = "application/atom+xml"
    env.response.status_code = status_code

    return "<error>#{exception.inspect_with_backtrace}</error>"
  end

  def error_atom_helper(env : HTTP::Server::Context, status_code : Int32, message : String)
    env.response.content_type = "application/atom+xml"
    env.response.status_code = status_code

    return "<error>#{message}</error>"
  end

  # -------------------
  #  JSON
  # -------------------

  macro error_json(*args)
    Errors.error_json_helper(env, {{ args.splat }})
  end

  def error_json_helper(
    env : HTTP::Server::Context,
    status_code : Int32,
    exception : Exception,
    additional_fields : Hash(String, Object)? = nil,
  )
    if exception.is_a?(InfoException)
      return error_json_helper(env, status_code, exception.message || "", additional_fields)
    end

    env.response.content_type = "application/json"
    env.response.status_code = status_code

    error_message = {"error" => exception.message, "errorBacktrace" => exception.inspect_with_backtrace}

    if additional_fields
      error_message = error_message.merge(additional_fields)
    end

    return error_message.to_json
  end

  def error_json_helper(
    env : HTTP::Server::Context,
    status_code : Int32,
    message : String,
    additional_fields : Hash(String, Object)? = nil,
  )
    env.response.content_type = "application/json"
    env.response.status_code = status_code

    error_message = {"error" => message}

    if additional_fields
      error_message = error_message.merge(additional_fields)
    end

    return error_message.to_json
  end

  # -------------------
  #  Redirect
  # -------------------

  def error_redirect_helper(env : HTTP::Server::Context, retry_request : Bool = false)
    path = env.request.path
    locale = env.get("preferences").as(Preferences).locale
    public_content = path == "/search" || path == "/watch" || path.starts_with?("/channel/") ||
                     path == "/mix" || (path == "/playlist" && env.params.query["list"]?.try &.starts_with?("PL"))
    resource = env.request.resource
    return "" unless resource.starts_with?("/") && !resource.starts_with?("//")

    String.build do |html|
      if retry_request || public_content
        html << %(<a href="#{HTML.escape(resource)}">#{I18n.translate(locale, "next_steps_error_message_refresh")}</a>)
      end
      if public_content
        redirect_url = "/redirect?referer=#{URI.encode_www_form(resource)}"
        html << %(<a href="#{HTML.escape(redirect_url)}">#{I18n.translate(locale, "Switch Invidious Instance")}</a>)
        youtube_path = path == "/mix" ? "/watch?v=#{URI.encode_www_form(env.params.query["continuation"]? || env.params.query["list"]?.try(&.lchop("RD")) || "")}&list=#{URI.encode_www_form(env.params.query["list"]? || "")}" : resource
        html << %(<a rel="noreferrer noopener" href="https://www.youtube.com#{HTML.escape(youtube_path)}">#{I18n.translate(locale, "next_steps_error_message_go_to_youtube")}</a>)
      end
    end
  end
end
