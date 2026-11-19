module Invidious::Database::SubscriptionFilters
  extend self

  VIDEO = 'v'
  SHORT = 's'
  LIVE  = 'l'

  def select(email : String) : Hash(String, String)
    PG_DB.query_all(
      "SELECT ucid, types FROM subscription_filters WHERE email = $1", email,
      as: {String, String}
    ).to_h
  end

  def save(email : String, ucid : String, types : String)
    PG_DB.exec(<<-SQL, email, ucid, types)
      INSERT INTO subscription_filters (email, ucid, types)
      SELECT email, $2, $3 FROM users WHERE email = $1 AND $2 = ANY(subscriptions)
      FOR UPDATE
      ON CONFLICT (email, ucid) DO UPDATE SET types = EXCLUDED.types
      SQL
  end

  def reset(email : String, ucid : String)
    PG_DB.exec("DELETE FROM subscription_filters WHERE email = $1 AND ucid = $2", email, ucid)
  end

  # Arguments are trusted SQL expressions; user values are bound separately.
  # Unknown uploads are treated as regular videos until classified.
  def allowed_sql(email : String, hide_shorts : String) : String
    <<-SQL
      COALESCE(
        (SELECT strpos(sf.types, CASE
          WHEN cv.is_livestream IS TRUE THEN 'l'
          WHEN cv.is_short IS TRUE THEN 's'
          ELSE 'v'
        END) > 0 FROM subscription_filters sf
        WHERE sf.email = #{email} AND sf.ucid = cv.ucid),
        NOT (#{hide_shorts} AND cv.is_short IS TRUE)
      )
      SQL
  end

  def allows_video?(user : User, video_id : String) : Bool
    filter = allowed_sql("$2", "$3")
    PG_DB.query_one?("SELECT #{filter} FROM channel_videos cv WHERE cv.id = $1",
      video_id, user.email, user.preferences.hide_shorts, as: Bool) != false
  end
end
