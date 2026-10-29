-- Supabase > SQL Editor এ পুরোটা পেস্ট করে Run করুন
-- (আগের schema চালিয়ে থাকলেও সমস্যা নেই, নিচের drop লাইনগুলো পুরনোটা মুছে নতুন করে বানাবে)

drop table if exists messages cascade;
drop table if exists owners cascade;
drop table if exists profiles cascade;
drop function if exists is_owner() cascade;
drop function if exists handle_new_user() cascade;
drop function if exists email_for_username(text) cascade;

create table profiles (
  id uuid primary key references auth.users on delete cascade,
  name text not null,
  username text not null unique,
  email text,
  phone text,
  created_at timestamptz default now()
);

create table messages (
  id bigint generated always as identity primary key,
  user_id uuid not null references profiles(id) on delete cascade, -- কোন ইউজারের সাথে কথোপকথন
  sender_id uuid not null references profiles(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 2000),
  created_at timestamptz default now()
);
create index on messages (user_id, created_at);

create table owners (id uuid primary key references auth.users on delete cascade);

create function is_owner() returns boolean
language sql security definer set search_path = public as
$$ select exists (select 1 from owners where id = auth.uid()) $$;

-- ইউজারনেম দিয়ে লগইনের জন্য: ইউজারনেম থেকে ইমেইল বের করে (লগইনের আগে লাগে)
create function email_for_username(u text) returns text
language sql security definer set search_path = public as
$$ select email from profiles where username = lower(u) $$;
grant execute on function email_for_username(text) to anon, authenticated;

-- সাইনআপ করলে অটো প্রোফাইল তৈরি
create function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, name, username, email, phone)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'name', 'User'),
    lower(coalesce(new.raw_user_meta_data->>'username', 'user' || substr(new.id::text, 1, 8))),
    new.email,
    nullif(new.raw_user_meta_data->>'phone', '')
  );
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function handle_new_user();

alter table profiles enable row level security;
alter table messages enable row level security;
alter table owners enable row level security;

create policy "own or owner can read profile" on profiles
  for select using (id = auth.uid() or is_owner());

create policy "read own conversation" on messages
  for select using (user_id = auth.uid() or is_owner());

create policy "user sends in own conversation" on messages
  for insert with check (user_id = auth.uid() and sender_id = auth.uid());

create policy "owner replies anywhere" on messages
  for insert with check (is_owner() and sender_id = auth.uid());

alter publication supabase_realtime add table messages;

-- শেষ ধাপ: আগে ওয়েবসাইটে নিজের একাউন্ট খুলুন, তারপর এটা Run করুন (ইমেইল বদলে):
-- insert into owners select id from auth.users where email = 'আপনার-ইমেইল@example.com';
