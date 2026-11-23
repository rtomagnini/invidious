module Invidious::Database::Migrations
  class AddMembersOnlyFilters < Migration
    version 13

    def up(conn : DB::Connection)
      conn.exec("ALTER TABLE channel_videos ADD COLUMN IF NOT EXISTS is_members_only boolean")
      conn.exec(<<-SQL)
        ALTER TABLE subscription_filters
          DROP CONSTRAINT IF EXISTS subscription_filters_types_check,
          ADD CONSTRAINT subscription_filters_types_check CHECK (types ~ '^v?s?l?m?$')
        SQL
      conn.exec("UPDATE users SET feed_needs_update = true")
    end
  end
end
