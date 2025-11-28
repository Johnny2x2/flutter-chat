# Flutter Chat Example

Simple chat app to demonstrate the realtime capability of Supabase with Flutter. You can follow along on how to build this app on [this article](https://supabase.com/blog/flutter-tutorial-building-a-chat-app).

You can also find an example using [row level security](https://supabase.com/docs/guides/auth/row-level-security) to provide chat rooms to enable 1 to 1 chats on the [`with-auth` branch](https://github.com/supabase-community/flutter-chat/tree/with_auth). 

## Features

- User authentication (register/login)
- Group chat rooms (Discord-style)
  - Create chat rooms with custom names
  - Invite multiple friends to a room
  - Invite more friends from within a chat room
  - Persistent chat rooms you can come back to
  - Real-time message updates
- Friends list management
  - Search and add friends by username
  - Accept or reject friend requests
  - View pending and sent friend requests
  - Remove friends

## SQL

```sql
-- *** Table definitions ***

create table if not exists public.profiles (
    id uuid references auth.users on delete cascade not null primary key,
    username varchar(24) not null unique,
    created_at timestamp with time zone default timezone('utc' :: text, now()) not null,

    -- username should be 3 to 24 characters long containing alphabets, numbers and underscores
    constraint username_validation check (username ~* '^[A-Za-z0-9_]{3,24}$')
);
comment on table public.profiles is 'Holds all of users profile information';

create table if not exists public.conversations (
    id uuid not null primary key default uuid_generate_v4(),
    name varchar(100),
    created_at timestamp with time zone default timezone('utc' :: text, now()) not null
);
comment on table public.conversations is 'Holds conversation/chat room information.';

create table if not exists public.conversation_participants (
    id uuid not null primary key default uuid_generate_v4(),
    conversation_id uuid references public.conversations(id) on delete cascade not null,
    profile_id uuid references public.profiles(id) on delete cascade not null,
    created_at timestamp with time zone default timezone('utc' :: text, now()) not null,

    -- Ensure unique participant per conversation
    constraint unique_participant unique (conversation_id, profile_id)
);
comment on table public.conversation_participants is 'Holds participants of each conversation.';

create table if not exists public.messages (
    id uuid not null primary key default uuid_generate_v4(),
    conversation_id uuid references public.conversations(id) on delete cascade not null,
    profile_id uuid default auth.uid() references public.profiles(id) on delete cascade not null,
    content varchar(500) not null,
    created_at timestamp with time zone default timezone('utc' :: text, now()) not null
);
comment on table public.messages is 'Holds individual messages within a conversation.';

create table if not exists public.friendships (
    id uuid not null primary key default uuid_generate_v4(),
    user_id uuid references public.profiles(id) on delete cascade not null,
    friend_id uuid references public.profiles(id) on delete cascade not null,
    status varchar(20) not null default 'pending',
    created_at timestamp with time zone default timezone('utc' :: text, now()) not null,

    -- Ensure user can't friend themselves
    constraint no_self_friendship check (user_id != friend_id),
    -- Ensure unique friendship pairs
    constraint unique_friendship unique (user_id, friend_id),
    -- Status must be one of: pending, accepted, rejected
    constraint valid_status check (status in ('pending', 'accepted', 'rejected'))
);
comment on table public.friendships is 'Holds friendship relationships between users.';

-- *** Add tables to the publication to enable realtime ***
alter publication supabase_realtime add table public.messages;
alter publication supabase_realtime add table public.friendships;
alter publication supabase_realtime add table public.conversations;
alter publication supabase_realtime add table public.conversation_participants;


-- Function to create a new row in profiles table upon signup
-- Also copies the username value from metadata
create or replace function handle_new_user() returns trigger as $$
    begin
        insert into public.profiles(id, username)
        values(new.id, new.raw_user_meta_data->>'username');

        return new;
    end;
$$ language plpgsql security definer;

-- Trigger to call `handle_new_user` when new user signs up
create trigger on_auth_user_created
    after insert on auth.users
    for each row
    execute function handle_new_user();
```
