-- SwiftCode Supabase Cloud Database Schema
-- Production-Grade SQL Schema with Row Level Security (RLS)

-- Enable UUID extension
create extension if not exists "uuid-ossp";

-- 1. USERS (Custom profiles referencing auth.users)
create table if not exists public.profiles (
    id uuid references auth.users on delete cascade primary key,
    email text unique not null,
    full_name text,
    avatar_url text,
    created_at timestamp with time zone default timezone('utc'::text, now()) not null,
    updated_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Enable RLS
alter table public.profiles enable row level security;

create policy "Users can view their own profile" on public.profiles
    for select using (auth.uid() = id);

create policy "Users can update their own profile" on public.profiles
    for update using (auth.uid() = id);

-- Trigger for auto-updating timestamps
create or replace function public.handle_updated_at()
returns trigger as $$
begin
    new.updated_at = timezone('utc'::text, now());
    return new;
end;
$$ language plpgsql;

create trigger set_profiles_updated_at
    before update on public.profiles
    for each row execute function public.handle_updated_at();


-- 2. PROJECTS
create table if not exists public.projects (
    id uuid default uuid_generate_v4() primary key,
    owner_id uuid references public.profiles(id) on delete cascade not null,
    name text not null,
    path text,
    repository_url text,
    is_favorite boolean default false not null,
    created_at timestamp with time zone default timezone('utc'::text, now()) not null,
    updated_at timestamp with time zone default timezone('utc'::text, now()) not null
);

alter table public.projects enable row level security;
create policy "Users can manage their own projects" on public.projects
    for all using (auth.uid() = owner_id);

create index idx_projects_owner_id on public.projects(owner_id);
create trigger set_projects_updated_at before update on public.projects
    for each row execute function public.handle_updated_at();


-- 3. WORKSPACE STATE
create table if not exists public.workspace_state (
    id uuid default uuid_generate_v4() primary key,
    owner_id uuid references public.profiles(id) on delete cascade not null,
    project_id uuid references public.projects(id) on delete cascade,
    open_tabs jsonb default '[]'::jsonb not null,
    active_tab_id text,
    sidebar_visible boolean default true not null,
    created_at timestamp with time zone default timezone('utc'::text, now()) not null,
    updated_at timestamp with time zone default timezone('utc'::text, now()) not null
);

alter table public.workspace_state enable row level security;
create policy "Users can manage their own workspace_state" on public.workspace_state
    for all using (auth.uid() = owner_id);

create index idx_workspace_state_owner_id on public.workspace_state(owner_id);


-- 4. SETTINGS
create table if not exists public.settings (
    id uuid default uuid_generate_v4() primary key,
    owner_id uuid references public.profiles(id) on delete cascade not null,
    key text not null,
    value text not null,
    created_at timestamp with time zone default timezone('utc'::text, now()) not null,
    updated_at timestamp with time zone default timezone('utc'::text, now()) not null,
    unique(owner_id, key)
);

alter table public.settings enable row level security;
create policy "Users can manage their own settings" on public.settings
    for all using (auth.uid() = owner_id);

create index idx_settings_owner_id_key on public.settings(owner_id, key);


-- 5. SNIPPETS
create table if not exists public.snippets (
    id uuid default uuid_generate_v4() primary key,
    owner_id uuid references public.profiles(id) on delete cascade not null,
    title text not null,
    content text not null,
    language text,
    tags text[],
    created_at timestamp with time zone default timezone('utc'::text, now()) not null,
    updated_at timestamp with time zone default timezone('utc'::text, now()) not null
);

alter table public.snippets enable row level security;
create policy "Users can manage their own snippets" on public.snippets
    for all using (auth.uid() = owner_id);

create index idx_snippets_owner_id on public.snippets(owner_id);


-- 6. CHAT HISTORY
create table if not exists public.chat_history (
    id uuid default uuid_generate_v4() primary key,
    owner_id uuid references public.profiles(id) on delete cascade not null,
    session_id text not null,
    messages jsonb default '[]'::jsonb not null,
    created_at timestamp with time zone default timezone('utc'::text, now()) not null,
    updated_at timestamp with time zone default timezone('utc'::text, now()) not null
);

alter table public.chat_history enable row level security;
create policy "Users can manage their own chat_history" on public.chat_history
    for all using (auth.uid() = owner_id);

create index idx_chat_history_owner_session on public.chat_history(owner_id, session_id);


-- 7. AGENT HISTORY
create table if not exists public.agent_history (
    id uuid default uuid_generate_v4() primary key,
    owner_id uuid references public.profiles(id) on delete cascade not null,
    task_id text not null,
    steps jsonb default '[]'::jsonb not null,
    status text not null,
    created_at timestamp with time zone default timezone('utc'::text, now()) not null,
    updated_at timestamp with time zone default timezone('utc'::text, now()) not null
);

alter table public.agent_history enable row level security;
create policy "Users can manage their own agent_history" on public.agent_history
    for all using (auth.uid() = owner_id);


-- 8. EXTENSIONS & EXTENSION SETTINGS
create table if not exists public.extensions (
    id uuid default uuid_generate_v4() primary key,
    owner_id uuid references public.profiles(id) on delete cascade not null,
    identifier text not null,
    name text not null,
    version text not null,
    is_enabled boolean default true not null,
    manifest jsonb,
    created_at timestamp with time zone default timezone('utc'::text, now()) not null,
    unique(owner_id, identifier)
);

alter table public.extensions enable row level security;
create policy "Users can manage their extensions" on public.extensions
    for all using (auth.uid() = owner_id);

create table if not exists public.extension_settings (
    id uuid default uuid_generate_v4() primary key,
    owner_id uuid references public.profiles(id) on delete cascade not null,
    extension_id uuid references public.extensions(id) on delete cascade not null,
    settings jsonb default '{}'::jsonb not null,
    created_at timestamp with time zone default timezone('utc'::text, now()) not null,
    updated_at timestamp with time zone default timezone('utc'::text, now()) not null
);

alter table public.extension_settings enable row level security;
create policy "Users can manage extension settings" on public.extension_settings
    for all using (auth.uid() = owner_id);


-- 9. RECENT PROJECTS
create table if not exists public.recent_projects (
    id uuid default uuid_generate_v4() primary key,
    owner_id uuid references public.profiles(id) on delete cascade not null,
    project_id uuid references public.projects(id) on delete cascade not null,
    last_opened timestamp with time zone default timezone('utc'::text, now()) not null,
    unique(owner_id, project_id)
);

alter table public.recent_projects enable row level security;
create policy "Users can manage recent_projects" on public.recent_projects
    for all using (auth.uid() = owner_id);


-- 10. BOOKMARKS & FAVORITES
create table if not exists public.bookmarks (
    id uuid default uuid_generate_v4() primary key,
    owner_id uuid references public.profiles(id) on delete cascade not null,
    file_path text not null,
    line_number integer not null,
    notes text,
    created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

alter table public.bookmarks enable row level security;
create policy "Users can manage bookmarks" on public.bookmarks
    for all using (auth.uid() = owner_id);

create table if not exists public.favorites (
    id uuid default uuid_generate_v4() primary key,
    owner_id uuid references public.profiles(id) on delete cascade not null,
    item_type text not null, -- 'file', 'project', etc
    item_identifier text not null,
    created_at timestamp with time zone default timezone('utc'::text, now()) not null,
    unique(owner_id, item_type, item_identifier)
);

alter table public.favorites enable row level security;
create policy "Users can manage favorites" on public.favorites
    for all using (auth.uid() = owner_id);


-- 11. PROMPT LIBRARY & AI PREFERENCES & EDITOR PREFERENCES
create table if not exists public.prompt_library (
    id uuid default uuid_generate_v4() primary key,
    owner_id uuid references public.profiles(id) on delete cascade not null,
    name text not null,
    prompt_text text not null,
    category text,
    created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

alter table public.prompt_library enable row level security;
create policy "Users can manage prompts" on public.prompt_library
    for all using (auth.uid() = owner_id);

create table if not exists public.ai_preferences (
    id uuid default uuid_generate_v4() primary key,
    owner_id uuid references public.profiles(id) on delete cascade not null,
    preferred_model text,
    temperature numeric default 0.7,
    max_tokens integer default 2048,
    system_instruction text,
    updated_at timestamp with time zone default timezone('utc'::text, now()) not null,
    unique(owner_id)
);

alter table public.ai_preferences enable row level security;
create policy "Users can manage ai preferences" on public.ai_preferences
    for all using (auth.uid() = owner_id);

create table if not exists public.editor_preferences (
    id uuid default uuid_generate_v4() primary key,
    owner_id uuid references public.profiles(id) on delete cascade not null,
    font_size integer default 14 not null,
    font_family text default 'SF Mono' not null,
    tab_size integer default 4 not null,
    word_wrap boolean default true not null,
    theme_id text default 'dark' not null,
    updated_at timestamp with time zone default timezone('utc'::text, now()) not null,
    unique(owner_id)
);

alter table public.editor_preferences enable row level security;
create policy "Users can manage editor preferences" on public.editor_preferences
    for all using (auth.uid() = owner_id);


-- 12. TERMINAL HISTORY & BUILD HISTORY & DIAGNOSTICS
create table if not exists public.terminal_history (
    id uuid default uuid_generate_v4() primary key,
    owner_id uuid references public.profiles(id) on delete cascade not null,
    command text not null,
    directory text,
    executed_at timestamp with time zone default timezone('utc'::text, now()) not null
);

alter table public.terminal_history enable row level security;
create policy "Users can manage terminal_history" on public.terminal_history
    for all using (auth.uid() = owner_id);

create table if not exists public.build_history (
    id uuid default uuid_generate_v4() primary key,
    owner_id uuid references public.profiles(id) on delete cascade not null,
    project_id uuid references public.projects(id) on delete cascade,
    scheme text,
    status text not null,
    duration_seconds numeric,
    logs text,
    created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

alter table public.build_history enable row level security;
create policy "Users can manage build_history" on public.build_history
    for all using (auth.uid() = owner_id);

create table if not exists public.diagnostics (
    id uuid default uuid_generate_v4() primary key,
    owner_id uuid references public.profiles(id) on delete cascade not null,
    category text not null,
    log_level text not null,
    message text not null,
    details jsonb,
    created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

alter table public.diagnostics enable row level security;
create policy "Users can manage diagnostics" on public.diagnostics
    for all using (auth.uid() = owner_id);


-- 13. CLOUD STATISTICS & SYNC METADATA
create table if not exists public.cloud_statistics (
    id uuid default uuid_generate_v4() primary key,
    owner_id uuid references public.profiles(id) on delete cascade not null,
    bytes_uploaded bigint default 0 not null,
    bytes_downloaded bigint default 0 not null,
    upload_count integer default 0 not null,
    download_count integer default 0 not null,
    conflict_count integer default 0 not null,
    failure_count integer default 0 not null,
    updated_at timestamp with time zone default timezone('utc'::text, now()) not null,
    unique(owner_id)
);

alter table public.cloud_statistics enable row level security;
create policy "Users can manage cloud_statistics" on public.cloud_statistics
    for all using (auth.uid() = owner_id);

create table if not exists public.sync_metadata (
    id uuid default uuid_generate_v4() primary key,
    owner_id uuid references public.profiles(id) on delete cascade not null,
    resource_name text not null,
    last_synced_at timestamp with time zone default timezone('utc'::text, now()) not null,
    local_version integer default 1 not null,
    server_version integer default 1 not null,
    hash_value text,
    unique(owner_id, resource_name)
);

alter table public.sync_metadata enable row level security;
create policy "Users can manage sync_metadata" on public.sync_metadata
    for all using (auth.uid() = owner_id);


-- 14. DEVICES & SESSIONS
create table if not exists public.devices (
    id uuid default uuid_generate_v4() primary key,
    owner_id uuid references public.profiles(id) on delete cascade not null,
    device_name text not null,
    device_type text,
    os_version text,
    last_active timestamp with time zone default timezone('utc'::text, now()) not null,
    unique(owner_id, device_name)
);

alter table public.devices enable row level security;
create policy "Users can manage their devices" on public.devices
    for all using (auth.uid() = owner_id);

create table if not exists public.sessions (
    id uuid default uuid_generate_v4() primary key,
    owner_id uuid references public.profiles(id) on delete cascade not null,
    token text,
    expires_at timestamp with time zone,
    created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

alter table public.sessions enable row level security;
create policy "Users can manage their sessions" on public.sessions
    for all using (auth.uid() = owner_id);


-- 15. NOTIFICATIONS
create table if not exists public.notifications (
    id uuid default uuid_generate_v4() primary key,
    owner_id uuid references public.profiles(id) on delete cascade not null,
    title text not null,
    body text not null,
    is_read boolean default false not null,
    created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

alter table public.notifications enable row level security;
create policy "Users can manage notifications" on public.notifications
    for all using (auth.uid() = owner_id);


-- 16. BACKUPS
create table if not exists public.backups (
    id uuid default uuid_generate_v4() primary key,
    owner_id uuid references public.profiles(id) on delete cascade not null,
    filename text not null,
    size_bytes bigint not null,
    manifest jsonb not null,
    created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

alter table public.backups enable row level security;
create policy "Users can manage backups" on public.backups
    for all using (auth.uid() = owner_id);


-- 17. ACTIVITY LOG
create table if not exists public.activity_log (
    id uuid default uuid_generate_v4() primary key,
    owner_id uuid references public.profiles(id) on delete cascade not null,
    event_type text not null,
    description text not null,
    metadata jsonb,
    created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

alter table public.activity_log enable row level security;
create policy "Users can view activity_log" on public.activity_log
    for select using (auth.uid() = owner_id);
create policy "Users can insert activity_log" on public.activity_log
    for insert with check (auth.uid() = owner_id);


-- 18. CONFLICTS
create table if not exists public.conflicts (
    id uuid default uuid_generate_v4() primary key,
    owner_id uuid references public.profiles(id) on delete cascade not null,
    table_name text not null,
    primary_key text not null,
    local_data text not null,
    cloud_data text not null,
    detected_at timestamp with time zone default timezone('utc'::text, now()) not null,
    resolved_at timestamp with time zone,
    resolved_by text
);

alter table public.conflicts enable row level security;
create policy "Users can manage conflicts" on public.conflicts
    for all using (auth.uid() = owner_id);
