-- Расширения
create extension if not exists "uuid-ossp";

-- ПРОФИЛИ ПОЛЬЗОВАТЕЛЕЙ
create table if not exists profiles (
  id           uuid references auth.users(id) on delete cascade primary key,
  role         text check (role in ('student', 'tutor')) not null,
  full_name    text not null,
  is_verified  boolean default false,
  created_at   timestamptz default now(),
  updated_at   timestamptz default now()
);

-- АНКЕТЫ РЕПЕТИТОРОВ
create table if not exists tutor_profiles (
  id             uuid references profiles(id) on delete cascade primary key,
  subject        text,
  about          text,
  price          integer check (price > 0),
  social_link    text not null default '',
  avatar_url     text,
  is_hidden      boolean default false,
  rating_avg     numeric(3,2) default 0,
  reviews_count  integer default 0,
  updated_at     timestamptz default now()
);

-- ОТЗЫВЫ
create table if not exists reviews (
  id          uuid default gen_random_uuid() primary key,
  tutor_id    uuid references profiles(id) on delete cascade not null,
  student_id  uuid references profiles(id) on delete cascade not null,
  rating      integer check (rating between 1 and 5) not null,
  text        text,
  created_at  timestamptz default now(),
  unique(tutor_id, student_id)
);

-- ЗАЯВКИ ОТ УЧЕНИКОВ
create table if not exists contact_requests (
  id              uuid default gen_random_uuid() primary key,
  tutor_id        uuid references profiles(id) on delete cascade not null,
  student_id      uuid references profiles(id) on delete set null,
  student_name    text not null,
  student_email   text not null,
  student_phone   text,
  message         text,
  status          text default 'new' check (status in ('new', 'done')),
  created_at      timestamptz default now()
);

-- ФУНКЦИЯ: автообновление рейтинга
create or replace function update_tutor_rating()
returns trigger as $$
declare target_id uuid;
begin
  target_id := coalesce(NEW.tutor_id, OLD.tutor_id);
  update tutor_profiles set
    rating_avg    = (select coalesce(round(avg(rating)::numeric,2),0) from reviews where tutor_id=target_id),
    reviews_count = (select count(*) from reviews where tutor_id=target_id)
  where id = target_id;
  return NEW;
end;
$$ language plpgsql;

create trigger review_rating_update
after insert or update or delete on reviews
for each row execute function update_tutor_rating();

-- RLS
alter table profiles         enable row level security;
alter table tutor_profiles   enable row level security;
alter table reviews          enable row level security;
alter table contact_requests enable row level security;

create policy "profiles_select"       on profiles         for select using (true);
create policy "profiles_insert"       on profiles         for insert with check (auth.uid()=id);
create policy "profiles_update"       on profiles         for update using (auth.uid()=id);

create policy "tutor_profiles_select" on tutor_profiles   for select using ((not is_hidden) or (auth.uid()=id));
create policy "tutor_profiles_insert" on tutor_profiles   for insert with check (auth.uid()=id);
create policy "tutor_profiles_update" on tutor_profiles   for update using (auth.uid()=id);

create policy "reviews_select"        on reviews          for select using (true);
create policy "reviews_insert"        on reviews          for insert with check (auth.uid()=student_id);

create policy "contact_requests_select" on contact_requests for select using (auth.uid()=tutor_id or auth.uid()=student_id);
create policy "contact_requests_insert" on contact_requests for insert with check (true);
create policy "contact_requests_update" on contact_requests for update using (auth.uid()=tutor_id);

-- STORAGE
insert into storage.buckets (id,name,public) values ('avatars','avatars',true) on conflict (id) do nothing;
create policy "avatars_public_read"   on storage.objects for select using (bucket_id='avatars');
create policy "avatars_owner_insert"  on storage.objects for insert with check (bucket_id='avatars' and auth.uid()::text=(storage.foldername(name))[1]);
create policy "avatars_owner_update"  on storage.objects for update using  (bucket_id='avatars' and auth.uid()::text=(storage.foldername(name))[1]);
