//
//  SupabaseConfig.swift
//  guido-1
//
//  Created by AI Assistant on 1/8/25.
//  Supabase configuration with project credentials
//

import Foundation

struct SupabaseConfig {
    // Replace with your Supabase project URL
    static let supabaseURL = "https://higfytbuamlsfyowbqrr.supabase.co"
    
    // Replace with your Supabase anon key
    static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhpZ2Z5dGJ1YW1sc2Z5b3dicXJyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTY1MjIwNDcsImV4cCI6MjA3MjA5ODA0N30.dfZPRiJVU9axguV1YqW5ocS401q8PmXXCcqXpIfweFs"
    
    // iOS client ID (matches GoogleService-Info.plist) - Supabase configured separately with web client
    static let googleClientID = "306994331391-6g25ut4tce04292teofjq06hph965fej.apps.googleusercontent.com"
    
    // OpenAI API Key (from Config.plist)
    static var openAIAPIKey: String {
        guard let path = Bundle.main.path(forResource: "Config", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path),
              let apiKey = plist["OpenAI_API_Key"] as? String else {
            fatalError("OpenAI API Key not found in Config.plist")
        }
        return apiKey
    }
}

/*
SETUP INSTRUCTIONS:

1. Create a Supabase project at https://supabase.com
2. Go to Settings > API in your Supabase dashboard
3. Copy your Project URL and anon/public key
4. Replace the values above
5. Rename this file to SupabaseConfig.swift
6. Add SupabaseConfig.swift to .gitignore to keep your keys secure

For Google OAuth:
1. Go to Google Cloud Console
2. Create a new project or select existing
3. Enable Google+ API
4. Create OAuth 2.0 credentials
5. Download GoogleService-Info.plist and add to your project
6. Add your client ID above

Row Level Security (RLS) Setup:
Run these SQL commands in your Supabase SQL editor:

-- Create profiles table
CREATE TABLE profiles (
    id UUID REFERENCES auth.users ON DELETE CASCADE,
    full_name TEXT,
    avatar_url TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    PRIMARY KEY (id)
);

-- Enable RLS
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "Users can view own profile" ON profiles
    FOR SELECT USING (auth.uid() = id);

CREATE POLICY "Users can update own profile" ON profiles
    FOR UPDATE USING (auth.uid() = id);

CREATE POLICY "Users can insert own profile" ON profiles
    FOR INSERT WITH CHECK (auth.uid() = id);

-- Create function to handle new user registration
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.profiles (id, full_name, avatar_url)
    VALUES (
        NEW.id,
        NEW.raw_user_meta_data->>'full_name',
        NEW.raw_user_meta_data->>'avatar_url'
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger for new user registration
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Create conversations table for user data
CREATE TABLE conversations (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    title TEXT,
    messages JSONB DEFAULT '[]'::jsonb,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable RLS on conversations
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;

-- Create policies for conversations
CREATE POLICY "Users can view own conversations" ON conversations
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own conversations" ON conversations
    FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own conversations" ON conversations
    FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own conversations" ON conversations
    FOR DELETE USING (auth.uid() = user_id);
*/
