CREATE TABLE IF NOT EXISTS public.subscription_filters
(
  email text NOT NULL REFERENCES public.users(email) ON DELETE CASCADE,
  ucid text NOT NULL,
  types text NOT NULL CHECK (types ~ '^v?s?l?m?$'),
  PRIMARY KEY (email, ucid)
);
