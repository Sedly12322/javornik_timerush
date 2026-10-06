-- ==========================================================
-- JAVORNÍK TIMERUSH - KOMPLETNÍ SUPABASE SCHÉMA A BEZPEČNOST
-- ==========================================================
-- Spusťte tento skript v Supabase: Dashboard -> SQL Editor -> New query -> Run
-- ==========================================================

-- 1. TABULKA PROFILŮ (PROFILES)
CREATE TABLE IF NOT EXISTS public.profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  username text NOT NULL,
  discriminator text NOT NULL,
  full_username text NOT NULL,
  email text,
  profile_picture text,
  created_at timestamptz DEFAULT now(),
  total_climbs integer DEFAULT 0,
  total_time_seconds integer DEFAULT 0,
  total_distance double precision DEFAULT 0.0,
  is_running boolean DEFAULT false,
  start_time timestamptz
);

ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS username text;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS discriminator text;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS full_username text;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS email text;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS profile_picture text;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT now();
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS total_climbs integer DEFAULT 0;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS total_time_seconds integer DEFAULT 0;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS total_distance double precision DEFAULT 0.0;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS is_running boolean DEFAULT false;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS start_time timestamptz;

CREATE INDEX IF NOT EXISTS idx_profiles_username ON public.profiles(username);
CREATE INDEX IF NOT EXISTS idx_profiles_full_username ON public.profiles(full_username);

-- 2. TABULKA HOR (MOUNTAINS)
CREATE TABLE IF NOT EXISTS public.mountains (
  id text PRIMARY KEY,
  name text NOT NULL,
  lat double precision NOT NULL,
  lng double precision NOT NULL
);

-- 3. TABULKA TRAS (TRAILS)
CREATE TABLE IF NOT EXISTS public.trails (
  id text PRIMARY KEY,
  mountain_id text NOT NULL REFERENCES public.mountains(id) ON DELETE CASCADE,
  name text NOT NULL,
  polyline text NOT NULL,
  description text DEFAULT '',
  color text DEFAULT '#2196F3',
  icon text DEFAULT 'hiking'
);

-- 4. TABULKA VÝŠLAPŮ (CLIMBS)
CREATE TABLE IF NOT EXISTS public.climbs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  mountain_id text NOT NULL,
  trail_id text NOT NULL,
  time text NOT NULL,
  time_seconds integer NOT NULL,
  distance_km double precision DEFAULT 0.0,
  date timestamptz DEFAULT now(),
  is_auto_finished boolean DEFAULT false
);

CREATE INDEX IF NOT EXISTS idx_climbs_leaderboard ON public.climbs(mountain_id, trail_id, time_seconds);
CREATE INDEX IF NOT EXISTS idx_climbs_user ON public.climbs(user_id);

-- 5. TABULKA STATISTIK PODLE HOR (MOUNTAIN_STATS)
CREATE TABLE IF NOT EXISTS public.mountain_stats (
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  mountain_id text NOT NULL,
  climbs_count integer DEFAULT 0,
  last_climb_date timestamptz DEFAULT now(),
  best_time_seconds integer DEFAULT 999999,
  best_time_str text DEFAULT '--:--',
  PRIMARY KEY (user_id, mountain_id)
);

-- 6. TABULKA PŘÁTELSTVÍ (FRIENDS)
CREATE TABLE IF NOT EXISTS public.friends (
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  friend_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  status text NOT NULL CHECK (status IN ('sent', 'received', 'accepted')),
  created_at timestamptz DEFAULT now(),
  PRIMARY KEY (user_id, friend_id)
);

CREATE INDEX IF NOT EXISTS idx_friends_user ON public.friends(user_id);
CREATE INDEX IF NOT EXISTS idx_friends_friend ON public.friends(friend_id);

-- ==========================================================
-- 7. STORAGE BUCKET PRO PROFILOVÉ FOTKY
-- ==========================================================
INSERT INTO storage.buckets (id, name, public)
VALUES ('user_images', 'user_images', true)
ON CONFLICT (id) DO UPDATE SET public = true;

-- ==========================================================
-- 8. ROW LEVEL SECURITY (RLS)
-- ==========================================================
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mountains ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trails ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.climbs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mountain_stats ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.friends ENABLE ROW LEVEL SECURITY;

-- Profily: všichni mohou číst (pro vyhledávání, žebříčky a přátele), upravovat pouze vlastník
DROP POLICY IF EXISTS "profiles_select_public" ON public.profiles;
CREATE POLICY "profiles_select_public" ON public.profiles FOR SELECT USING (true);

DROP POLICY IF EXISTS "profiles_insert_own" ON public.profiles;
CREATE POLICY "profiles_insert_own" ON public.profiles FOR INSERT WITH CHECK (auth.uid() = id);

DROP POLICY IF EXISTS "profiles_update_own" ON public.profiles;
CREATE POLICY "profiles_update_own" ON public.profiles FOR UPDATE USING (auth.uid() = id);

-- Hory: veřejné čtení, úpravy pouze admin/service_role
DROP POLICY IF EXISTS "mountains_select_public" ON public.mountains;
CREATE POLICY "mountains_select_public" ON public.mountains FOR SELECT USING (true);

-- Trasy: veřejné čtení, úpravy pouze admin/service_role
DROP POLICY IF EXISTS "trails_select_public" ON public.trails;
CREATE POLICY "trails_select_public" ON public.trails FOR SELECT USING (true);

-- Výšlapy: veřejné čtení pro žebříčky a profily, vkládání a úpravy pouze pro přihlášeného uživatele pro jeho data
DROP POLICY IF EXISTS "climbs_select_public" ON public.climbs;
CREATE POLICY "climbs_select_public" ON public.climbs FOR SELECT USING (true);

DROP POLICY IF EXISTS "climbs_insert_own" ON public.climbs;
CREATE POLICY "climbs_insert_own" ON public.climbs FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "climbs_update_own" ON public.climbs;
CREATE POLICY "climbs_update_own" ON public.climbs FOR UPDATE USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "climbs_delete_own" ON public.climbs;
CREATE POLICY "climbs_delete_own" ON public.climbs FOR DELETE USING (auth.uid() = user_id);

-- Statistiky hor: veřejné čtení, zápis pouze vlastník
DROP POLICY IF EXISTS "mountain_stats_select_public" ON public.mountain_stats;
CREATE POLICY "mountain_stats_select_public" ON public.mountain_stats FOR SELECT USING (true);

DROP POLICY IF EXISTS "mountain_stats_modify_own" ON public.mountain_stats;
CREATE POLICY "mountain_stats_modify_own" ON public.mountain_stats FOR ALL USING (auth.uid() = user_id);

-- Přátelé: uživatel vidí své žádosti a své přátele
DROP POLICY IF EXISTS "friends_select" ON public.friends;
CREATE POLICY "friends_select" ON public.friends FOR SELECT USING (auth.uid() = user_id OR auth.uid() = friend_id);

DROP POLICY IF EXISTS "friends_modify" ON public.friends;
CREATE POLICY "friends_modify" ON public.friends FOR ALL USING (auth.uid() = user_id OR auth.uid() = friend_id);

-- Storage (Profilové obrázky)
DROP POLICY IF EXISTS "storage_select_user_images" ON storage.objects;
CREATE POLICY "storage_select_user_images" ON storage.objects FOR SELECT USING (bucket_id = 'user_images');

DROP POLICY IF EXISTS "storage_insert_user_images" ON storage.objects;
CREATE POLICY "storage_insert_user_images" ON storage.objects FOR INSERT WITH CHECK (
  bucket_id = 'user_images' AND auth.role() = 'authenticated'
);

DROP POLICY IF EXISTS "storage_update_user_images" ON storage.objects;
CREATE POLICY "storage_update_user_images" ON storage.objects FOR UPDATE USING (
  bucket_id = 'user_images' AND auth.role() = 'authenticated'
);

-- ==========================================================
-- 9. SERVEROVÉ RPC FUNKCE (BEZPEČNÉ A ATOMICKÉ OPERACE)
-- ==========================================================

-- A) Automatické vytvoření profilu při registraci (Google OAuth i Email)
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
DECLARE
  v_name text;
  v_disc text;
BEGIN
  v_name := COALESCE(
    new.raw_user_meta_data->>'full_name',
    new.raw_user_meta_data->>'name',
    split_part(new.email, '@', 1),
    'Horal'
  );
  v_disc := '#' || floor(1000 + random() * 9000)::text;

  INSERT INTO public.profiles (
    id,
    username,
    discriminator,
    full_username,
    email,
    profile_picture,
    created_at,
    total_climbs,
    total_time_seconds,
    total_distance,
    is_running
  ) VALUES (
    new.id,
    v_name,
    v_disc,
    v_name || v_disc,
    new.email,
    COALESCE(new.raw_user_meta_data->>'avatar_url', new.raw_user_meta_data->>'picture', null),
    now(),
    0,
    0,
    0.0,
    false
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- B) Atomické odeslání žádosti o přátelství
CREATE OR REPLACE FUNCTION public.send_friend_request(target_user_id uuid)
RETURNS void AS $$
DECLARE
  v_me uuid := auth.uid();
BEGIN
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'Uživatel není přihlášen';
  END IF;
  IF v_me = target_user_id THEN
    RAISE EXCEPTION 'Nemůžete přidat sám sebe';
  END IF;

  -- 1. U odesílatele
  INSERT INTO public.friends (user_id, friend_id, status, created_at)
  VALUES (v_me, target_user_id, 'sent', now())
  ON CONFLICT (user_id, friend_id) DO UPDATE SET status = 'sent';

  -- 2. U příjemce
  INSERT INTO public.friends (user_id, friend_id, status, created_at)
  VALUES (target_user_id, v_me, 'received', now())
  ON CONFLICT (user_id, friend_id) DO UPDATE SET status = 'received';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- C) Atomické přijetí žádosti o přátelství
CREATE OR REPLACE FUNCTION public.accept_friend_request(target_user_id uuid)
RETURNS void AS $$
DECLARE
  v_me uuid := auth.uid();
BEGIN
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'Uživatel není přihlášen';
  END IF;

  UPDATE public.friends
  SET status = 'accepted'
  WHERE (user_id = v_me AND friend_id = target_user_id)
     OR (user_id = target_user_id AND friend_id = v_me);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- D) Atomické odebrání přítele / zrušení žádosti
CREATE OR REPLACE FUNCTION public.remove_friend(target_user_id uuid)
RETURNS void AS $$
DECLARE
  v_me uuid := auth.uid();
BEGIN
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'Uživatel není přihlášen';
  END IF;

  DELETE FROM public.friends
  WHERE (user_id = v_me AND friend_id = target_user_id)
     OR (user_id = target_user_id AND friend_id = v_me);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- E) Atomický zápis výšlapu a aktualizace všech statistik v jedné transakci
CREATE OR REPLACE FUNCTION public.record_climb(
  p_mountain_id text,
  p_trail_id text,
  p_time_str text,
  p_time_seconds integer,
  p_distance_km double precision
)
RETURNS void AS $$
DECLARE
  v_me uuid := auth.uid();
  v_cur_best integer;
BEGIN
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'Uživatel není přihlášen';
  END IF;

  -- 1. Zápis výšlapu
  INSERT INTO public.climbs (
    user_id, mountain_id, trail_id, time, time_seconds, distance_km, date, is_auto_finished
  ) VALUES (
    v_me, p_mountain_id, p_trail_id, p_time_str, p_time_seconds, p_distance_km, now(), true
  );

  -- 2. Aktualizace celkových statistik uživatele
  UPDATE public.profiles
  SET
    total_climbs = COALESCE(total_climbs, 0) + 1,
    total_time_seconds = COALESCE(total_time_seconds, 0) + p_time_seconds,
    total_distance = COALESCE(total_distance, 0.0) + p_distance_km,
    is_running = false
  WHERE id = v_me;

  -- 3. Aktualizace statistik dané hory
  SELECT best_time_seconds INTO v_cur_best
  FROM public.mountain_stats
  WHERE user_id = v_me AND mountain_id = p_mountain_id;

  IF NOT FOUND THEN
    INSERT INTO public.mountain_stats (
      user_id, mountain_id, climbs_count, last_climb_date, best_time_seconds, best_time_str
    ) VALUES (
      v_me, p_mountain_id, 1, now(), p_time_seconds, p_time_str
    );
  ELSE
    UPDATE public.mountain_stats
    SET
      climbs_count = climbs_count + 1,
      last_climb_date = now(),
      best_time_seconds = LEAST(best_time_seconds, p_time_seconds),
      best_time_str = CASE WHEN p_time_seconds < best_time_seconds THEN p_time_str ELSE best_time_str END
    WHERE user_id = v_me AND mountain_id = p_mountain_id;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ==========================================================
-- 10. VÝCHOZÍ DATA HOR A TRAS (pokud ještě neexistují)
-- ==========================================================
INSERT INTO public.mountains (id, name, lat, lng)
VALUES ('Velký Javorník', 'Velký Javorník', 49.5273, 18.1633)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.trails (id, mountain_id, name, polyline, description, color, icon)
VALUES (
  'trail_javornik_cervena',
  'Velký Javorník',
  'Červená z Frenštátu',
  'm~i{HqfgxBs@k@k@m@s@eAo@y@o@u@q@w@m@k@s@_Ai@iAc@s@_AcAcAcA}AwAwAsA_BuAyAsAmAoAy@sAcAmAw@q@o@w@o@q@w@',
  'Klasická turistická trasa z Frenštátu pod Radhoštěm.',
  '#E53935',
  'hiking'
)
ON CONFLICT (id) DO NOTHING;
