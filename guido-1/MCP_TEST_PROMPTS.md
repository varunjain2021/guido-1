# MCP Servers Testing Prompts (Comprehensive)

Use these prompts to exercise all active MCP servers and flows. Watch logs for server routing markers:
- 🗺️ LocationMCPServer
- 🧳 TravelMCPServer
- 🔎 SearchMCPServer

## 0) Setup and Flags
- Ensure keys in `Config.plist`: `OpenAI_API_Key`, `ElevenLabs_API_Key`, `Google_API_Key`, `OpenWeather_API_Key` (optional; weather falls back with clear error if missing).
- Default migration state: MCP with legacy fallback.
- Optional: Hybrid mode per category
  - Enable Location only: set migration to Hybrid and enable category Location; expect only location tools to route 🗺️.
  - Disable Travel/Search categories to verify legacy fallback.

Expected logs when connected:
- “✅ [MCP] Connected to in-process MCP server”
- “✅ [MCPToolCoordinator] Registered X location tools …” (and travel/search when enabled)

---

## 1) Location (Nearby + Directions)

### 1.1 Location Context
- “Where am I?”
  - Expect 📍 lat/lon, address, movement; logs: 🗺️ executing get_user_location

### 1.2 Nearby Places (MECE categories)
- “Find nearby restaurants within 1000 meters”
- “Find attractions within 2000 meters”
- “Find hotels around here”
- “Find entertainment nearby”
- “Find medical services near me”
- “Find gas stations within 500 meters”
  - Expect: 🔎/🗺️ places search via Google (for generic places) or LocationBasedSearchService for specific verticals; clear summaries, examples.

### 1.3 Transport
- “What’s the nearest subway station?” (subway)
- “Find bus stations near me” (bus)
- “Where’s the nearest train station?” (train)
- “Find taxi stands nearby” (taxi)
- “Find parking within 500 meters” (parking)
  - Expect: 🗺️ find_nearby_transport; Google Places path preferred; summary with top matches.

### 1.4 Landmarks
- “Show me landmarks nearby”
- “Find museums near me”
- “Find parks around here”
  - Expect: 🗺️ find_nearby_landmarks; structured summary.

### 1.5 Services
- “Find pharmacies near me”
- “Find ATMs within 500 meters”
- “Find hospitals nearby”
  - Expect: 🗺️ find_nearby_services; structured summary.

### 1.6 Restaurants (dedicated)
- “Find Italian restaurants nearby” (cuisine only)
- “Find sushi near me” (query)
- “Find coffee shops within 500 meters” (query + radius)
  - Expect: 🗺️ find_nearby_restaurants using LocationBasedSearchService; summarized results.

### 1.7 Directions (Google Routes)
- Simple address:
  - “Give me walking directions to 351 Amsterdam Ave, New York, NY” → 🗺️ get_directions → Google Routes, distance/duration summary.
- Place name (requires resolution and confirmation):
  - “Directions to Levain Bakery” → Expect a confirmation prompt:
    - “I found Levain Bakery at 351 Amsterdam Ave, ~1.2 km away (~15 min walk). Is this right, and how are you getting there (walking/driving/transit/cycling)?”
    - Reply: “Yes, that one. Walking.” → Returns walking route summary.
- Ambiguous place:
  - “Directions to Central Park entrance” → ask for which entrance or address; after confirmation, return route.
- Modes:
  - “Transit directions to 72 St subway station”
  - “Cycling directions to American Museum of Natural History”

Edge checks:
- Invalid address → clear error from Routes
- Timeout/network → fallback message

---

## 2) Travel (Real Providers)

### 2.1 Weather (OpenWeather)
- “What’s the weather like right here?”
- “Weather for the next day here” (forecast_days is tolerated even if current-only summary)
- Missing OpenWeather key → expect clear “Weather service unavailable/missing key”

### 2.2 Currency Conversion (exchangerate.host)
- “Convert 50 USD to EUR”
- “Convert 1234.56 JPY to GBP”
- Invalid currency code: “Convert 10 AAA to BBB” → expect error message

### 2.3 Translation (OpenAI)
- “Translate ‘Good evening’ to French”
- “Translate to Spanish: ‘Where is the nearest subway station?’”
- With source: “Translate from ja to en: ‘ありがとうございます’”
- Long text paragraph → verify clean output

---

## 3) Search (General Web + AI Summaries)

### 3.1 Web Search (Location-aware query composition)
- “Search the web for live events happening this weekend on the Upper West Side”
- “Search for best coffee shops in NYC open late tonight”
- With `location` context: “Search for farmer’s markets”, location=“New York City”
  - Expect: 🔎 web_search using LocationBasedSearchService; summarized results.

### 3.2 AI Response
- “Summarize the best things to do in NYC tonight for a foodie”
- “Plan a 1-day walking itinerary in the Upper West Side with 2 museums and a bakery stop” (context-rich)
  - Expect: 🔎 ai_response using OpenAIChatService; coherent multi-step answer.

---

## 4) Confirmation & Multi-turn Flows
- Place resolution + mode confirmation:
  - “Can you guide me to Levain Bakery?” → confirm address + distance → “Walking.”
- Change of mind:
  - After confirming place: “Actually, transit.” → re-route with transit mode.
- Ambiguity resolution:
  - “Directions to Central Park” → “Which entrance? 72nd Street or 81st Street?”

---

## 5) Fallbacks, Flags, and Routing
- Hybrid Location Only:
  - Enable Location category in Hybrid; issue: “Where am I?”, “Find pharmacies near me” → expect 🗺️ routing; Travel/Search fall back to legacy (no 🧳/🔎).
- Disable Travel category:
  - “Convert 50 USD to EUR” → verify legacy fallback or an intentional error if MCP-only.
- Error Injection:
  - Temporarily remove `Google_API_Key` → Nearby/Transport/Directions should show clear errors and/or fallback behavior.

Expected routing logs:
- “Routing 'find_nearby_transport' to LocationMCPServer”
- “Routing 'get_weather' to TravelMCPServer”
- “Routing 'web_search' to SearchMCPServer”

---

## 6) Edge Cases & Robustness
- No GPS / location denied → Nearby tools should return clear “Location not available”.
- Radius edge values: 500 / 5000 meters.
- International characters in translation and search.
- Large currency amounts and rounding.
- Network failure simulation (turn off network): expect graceful errors.

---

## 7) Performance & Regression Checks
- Measure first-byte latency for Nearby vs Directions vs Weather (subjective logs timing).
- Ensure no audio/VAD regressions while tools run.
- Confirm tool counts and registrations at startup; compare to expected.

---

## 8) Quick Copy Prompts
- “Where am I?”
- “Find attractions within 2000 meters”
- “What’s the nearest subway station?”
- “Directions to 351 Amsterdam Ave, New York, NY (walking)”
- “Can you guide me to Levain Bakery?” → “Yes, 351 Amsterdam Ave” → “Walking”
- “What’s the weather like right here?”
- “Convert 50 USD to EUR”
- “Translate ‘Good evening’ to French”
- “Search the web for live events on the Upper West Side this weekend”
- “Summarize the best things to do in NYC tonight for a foodie”