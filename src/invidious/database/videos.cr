require "./base.cr"

module Invidious::Database::Videos
  extend self

  def insert(video : Video)
    request = <<-SQL
      INSERT INTO videos
      VALUES ($1, $2, $3)
      ON CONFLICT (id) DO NOTHING
      SQL

    PG_DB.exec(request, video.id, video.info.to_json, video.updated)
  end

  def delete(id)
    request = <<-SQL
      DELETE FROM videos *
      WHERE id = $1
      SQL

    PG_DB.exec(request, id)
  end

  def delete_expired
    request = <<-SQL
      DELETE FROM videos *
      WHERE updated < (now() - interval '6 hours')
      SQL

    PG_DB.exec(request)
  end

  def update(video : Video)
    request = <<-SQL
      UPDATE videos
      SET (id, info, updated) = ($1, $2, $3)
      WHERE id = $1
      SQL

    PG_DB.exec(request, video.id, video.info.to_json, video.updated)
  end

  def select_history_entries(ids : Array(String)) : Array({String, String?, String?, String?})
    return [] of {String, String?, String?, String?} if ids.empty?

    PG_DB.query_all(<<-SQL, ids, as: {String, String?, String?, String?})
      SELECT watched.id,
        COALESCE(NULLIF(v.info::jsonb ->> 'title', ''), cv.title),
        COALESCE(NULLIF(v.info::jsonb ->> 'author', ''), cv.author),
        COALESCE(NULLIF(v.info::jsonb ->> 'lengthSeconds', '0'), cv.length_seconds::text)
      FROM unnest($1::text[]) WITH ORDINALITY AS watched(id, position)
      LEFT JOIN videos v ON v.id = watched.id
      LEFT JOIN channel_videos cv ON cv.id = watched.id
      ORDER BY watched.position
      SQL
  end

  def select(id : String) : Video?
    request = <<-SQL
      SELECT * FROM videos
      WHERE id = $1
      SQL

    return PG_DB.query_one?(request, id, as: Video)
  end
end
