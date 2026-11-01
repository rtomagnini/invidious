module Invidious::Database::Migrations
  class AddShortsClassification < Migration
    version 11

    def up(conn : DB::Connection)
      conn.exec("ALTER TABLE channel_videos ADD COLUMN IF NOT EXISTS is_short boolean")
      conn.exec("ALTER TABLE channels ADD COLUMN IF NOT EXISTS shorts_continuation text")
      conn.exec("UPDATE users SET feed_needs_update = true")
    end
  end
end
