require "http/cookie"

struct Invidious::User
  module Cookies
    extend self

    # Note: we use ternary operator because the two variables
    # used in here are not booleans.
    @@secure = (Kemal.config.ssl || CONFIG.https_only) ? true : false

    # Session ID (SID) cookie
    # Parameter "domain" comes from the global config
    def sid(domain : String?, sid) : HTTP::Cookie
      # Not secure if it's being accessed from I2P
      # Browsers expect the domain to include https. On I2P there is no HTTPS
      # Tor browser works fine with secure being true
      if (domain.try &.split(".").last == "i2p") && @@secure
        @@secure = false
      end

      return HTTP::Cookie.new(
        name: "SID",
        domain: domain,
        value: sid,
        expires: Time.utc + 2.years,
        secure: @@secure,
        http_only: true,
        samesite: HTTP::Cookie::SameSite::Lax
      )
    end

    FEEDBACK_KEYS = {"feedback_history_cleared", "feedback_account_deleted", "feedback_filter_saved",
                     "feedback_watched", "feedback_unwatched", "feedback_playlist_added", "feedback_playlist_removed", "feedback_imported"}

    def set_feedback(env, key : String)
      env.response.cookies << feedback_cookie(key, Time.utc + 2.minutes)
    end

    def take_feedback(env) : String?
      if cookie = env.request.cookies["IV_FEEDBACK"]?
        env.response.cookies << feedback_cookie("", Time.utc(1990, 1, 1))
        env.response.headers["Cache-Control"] = "no-store"
        return cookie.value if FEEDBACK_KEYS.includes?(cookie.value)
      end
    end

    private def feedback_cookie(value, expires)
      HTTP::Cookie.new(name: "IV_FEEDBACK", value: value, expires: expires, path: "/",
        secure: @@secure, http_only: true, samesite: HTTP::Cookie::SameSite::Lax)
    end

    # Preferences (PREFS) cookie
    # Parameter "domain" comes from the global config
    def prefs(domain : String?, preferences : Preferences) : HTTP::Cookie
      # Not secure if it's being accessed from I2P
      # Browsers expect the domain to include https. On I2P there is no HTTPS
      # Tor browser works fine with secure being true
      if (domain.try &.split(".").last == "i2p") && @@secure
        @@secure = false
      end

      return HTTP::Cookie.new(
        name: "PREFS",
        domain: domain,
        value: URI.encode_www_form(preferences.to_json),
        expires: Time.utc + 2.years,
        secure: @@secure,
        http_only: false,
        samesite: HTTP::Cookie::SameSite::Lax
      )
    end
  end
end
