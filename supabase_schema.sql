-- ==========================================================
-- JAVORNÍK TIMERUSH - SUPABASE DATABÁZOVÉ SCHÉMA
-- ==========================================================
-- Tento SQL skript spusťte v Supabase v sekci: SQL Editor -> New Query
-- ==========================================================

-- 0. VYČIŠTĚNÍ STARÝCH/KONFLIKTNÍCH TABULEK A POHLEDŮ (pokud byly dříve vytvořeny s jinými typy např. UUID)
DROP MATERIALIZED VIEW IF EXISTS public.mountain_stats CASCADE;
DROP VIEW IF EXISTS public.mountain_stats CASCADE;

DROP TABLE IF EXISTS public.friends CASCADE;
DROP TABLE IF EXISTS public.mountain_stats CASCADE;
DROP TABLE IF EXISTS public.climbs CASCADE;
DROP TABLE IF EXISTS public.trails CASCADE;
DROP TABLE IF EXISTS public.mountains CASCADE;

-- 1. TABULKA PROFILŮ UŽIVATELŮ
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

-- Zajištění sloupců, pokud již profiles existovala
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

-- 2. TABULKA HOR
CREATE TABLE public.mountains (
  id text PRIMARY KEY,
  name text NOT NULL,
  lat double precision NOT NULL,
  lng double precision NOT NULL
);

-- 3. TABULKA TRAS (TRAILS)
CREATE TABLE public.trails (
  id text PRIMARY KEY,
  mountain_id text NOT NULL REFERENCES public.mountains(id) ON DELETE CASCADE,
  name text NOT NULL,
  polyline text NOT NULL,
  description text DEFAULT '',
  color text DEFAULT '#2196F3',
  icon text DEFAULT 'hiking'
);

-- 4. TABULKA VÝŠLAPŮ (CLIMBS)
CREATE TABLE public.climbs (
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

-- 5. TABULKA STATISTIK PODLE HOR (MOUNTAIN_STATS)
CREATE TABLE public.mountain_stats (
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  mountain_id text NOT NULL,
  climbs_count integer DEFAULT 0,
  last_climb_date timestamptz DEFAULT now(),
  best_time_seconds integer DEFAULT 999999,
  best_time_str text DEFAULT '--:--',
  PRIMARY KEY (user_id, mountain_id)
);

-- 6. TABULKA PŘÁTELSTVÍ (FRIENDS)
CREATE TABLE public.friends (
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  friend_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  status text NOT NULL CHECK (status IN ('sent', 'received', 'accepted')),
  created_at timestamptz DEFAULT now(),
  PRIMARY KEY (user_id, friend_id)
);

-- ==========================================================
-- STORAGE BUCKET PRO PROFILOVÉ FOTKY
-- ==========================================================
INSERT INTO storage.buckets (id, name, public)
VALUES ('user_images', 'user_images', true)
ON CONFLICT (id) DO UPDATE SET public = true;

-- ==========================================================
-- ROW LEVEL SECURITY (RLS) & POLICIES
-- ==========================================================
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mountains ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trails ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.climbs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mountain_stats ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.friends ENABLE ROW LEVEL SECURITY;

-- Profily
DROP POLICY IF EXISTS "Veřejné čtení profilů" ON public.profiles;
CREATE POLICY "Veřejné čtení profilů" ON public.profiles FOR SELECT USING (true);

DROP POLICY IF EXISTS "Uživatel může vkládat profil" ON public.profiles;
CREATE POLICY "Uživatel může vkládat profil" ON public.profiles FOR INSERT WITH CHECK (auth.uid() = id OR auth.uid() IS NULL);

DROP POLICY IF EXISTS "Uživatel může upravovat svůj profil" ON public.profiles;
CREATE POLICY "Uživatel může upravovat svůj profil" ON public.profiles FOR ALL USING (auth.uid() = id);

-- Hory
DROP POLICY IF EXISTS "Veřejné čtení hor" ON public.mountains;
CREATE POLICY "Veřejné čtení hor" ON public.mountains FOR SELECT USING (true);

-- Trasy
DROP POLICY IF EXISTS "Veřejné čtení tras" ON public.trails;
CREATE POLICY "Veřejné čtení tras" ON public.trails FOR SELECT USING (true);

-- Výšlapy
DROP POLICY IF EXISTS "Veřejné čtení výšlapů" ON public.climbs;
CREATE POLICY "Veřejné čtení výšlapů" ON public.climbs FOR SELECT USING (true);

DROP POLICY IF EXISTS "Uživatel může vkládat výšlapy" ON public.climbs;
CREATE POLICY "Uživatel může vkládat výšlapy" ON public.climbs FOR INSERT WITH CHECK (auth.uid() = user_id OR auth.uid() IS NULL);

-- Statistiky hor
DROP POLICY IF EXISTS "Veřejné čtení statistik hor" ON public.mountain_stats;
CREATE POLICY "Veřejné čtení statistik hor" ON public.mountain_stats FOR SELECT USING (true);

DROP POLICY IF EXISTS "Uživatel může upravovat statistiky hor" ON public.mountain_stats;
CREATE POLICY "Uživatel může upravovat statistiky hor" ON public.mountain_stats FOR ALL USING (auth.uid() = user_id OR auth.uid() IS NULL);

-- Přátelé
DROP POLICY IF EXISTS "Správa přátelství" ON public.friends;
CREATE POLICY "Správa přátelství" ON public.friends FOR ALL USING (auth.uid() = user_id OR auth.uid() = friend_id);

-- Storage (Fotky)
DROP POLICY IF EXISTS "Veřejné stahování profilových fotek" ON storage.objects;
CREATE POLICY "Veřejné stahování profilových fotek" ON storage.objects FOR SELECT USING (bucket_id = 'user_images');

DROP POLICY IF EXISTS "Nahrávání profilových fotek" ON storage.objects;
CREATE POLICY "Nahrávání profilových fotek" ON storage.objects FOR INSERT WITH CHECK (bucket_id = 'user_images');

DROP POLICY IF EXISTS "Aktualizace profilových fotek" ON storage.objects;
CREATE POLICY "Aktualizace profilových fotek" ON storage.objects FOR UPDATE USING (bucket_id = 'user_images');

-- ==========================================================
-- UKÁZKOVÁ VÝCHOZÍ DATA
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
