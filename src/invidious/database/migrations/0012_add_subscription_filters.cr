module Invidious::Database::Migrations
  class AddSubscriptionFilters < Migration
    version 12

    def up(conn : DB::Connection)
      conn.exec(File.read("config/sql/subscription_filters.sql"))
      conn.exec("ALTER TABLE channel_videos ADD COLUMN IF NOT EXISTS is_livestream boolean")
      conn.exec("ALTER TABLE channels ADD COLUMN IF NOT EXISTS livestreams_continuation text")
      conn.exec("UPDATE users SET feed_needs_update = true")
    end
  end
end
