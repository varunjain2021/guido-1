import Foundation

public class TravelMCPServer {
    private weak var locationManager: LocationManager?
    private weak var openAIChatService: OpenAIChatService?
    private weak var weatherService: WeatherService?
    private weak var currencyService: CurrencyService?
    private weak var translationService: TranslationService?
    private weak var travelRequirementsService: TravelRequirementsService?
    private let serverInfo = MCPServerInfo(name: "Guido Travel Server", version: "1.0.0")
    
    init(locationManager: LocationManager? = nil) {
        self.locationManager = locationManager
    }
    
    func setLocationManager(_ manager: LocationManager) {
        self.locationManager = manager
    }
    
    func setOpenAIChatService(_ service: OpenAIChatService) {
        self.openAIChatService = service
    }
    
    func setWeatherService(_ service: WeatherService) {
        self.weatherService = service
    }
    
    func setCurrencyService(_ service: CurrencyService) {
        self.currencyService = service
    }
    
    func setTranslationService(_ service: TranslationService) {
        self.translationService = service
    }
    
    func setTravelRequirementsService(_ service: TravelRequirementsService) {
        self.travelRequirementsService = service
    }
    
    public func getCapabilities() -> MCPCapabilities {
        return MCPCapabilities(tools: MCPToolsCapability(listChanged: true), resources: nil, prompts: nil, sampling: nil)
    }
    
    public func getServerInfo() -> MCPServerInfo {
        return serverInfo
    }
    
    public func listTools() -> [MCPTool] {
        return [
            getWeatherTool(),
            getCurrencyTool(),
            getTranslationTool()
        ]
    }
    
    public func callTool(_ request: MCPCallToolRequest) async -> MCPCallToolResponse {
        print("🧳 [TravelMCPServer] Executing tool: \(request.name)")
        switch request.name {
        case "get_weather":
            return await executeGetWeather(request)
        case "currency_converter":
            return await executeCurrency(request)
        case "translate_text":
            return await executeTranslate(request)
        case "check_travel_requirements":
            return MCPCallToolResponse(content: [MCPContent(text: "Travel requirements not supported")], isError: true)
        default:
            return MCPCallToolResponse(content: [MCPContent(text: "Tool '\(request.name)' not found")], isError: true)
        }
    }
    
    private func getWeatherTool() -> MCPTool {
        return MCPTool(
            name: "get_weather",
            description: "Get current weather and forecast",
            inputSchema: MCPToolInputSchema(properties: [
                "location": MCPPropertySchema(type: "string", description: "City name (optional)"),
                "forecast_days": MCPPropertySchema(type: "string", description: "Days of forecast", enumValues: ["1","3","5","7"])
            ], required: [])
        )
    }
    
    private func getCurrencyTool() -> MCPTool {
        return MCPTool(
            name: "currency_converter",
            description: "Convert currency amounts",
            inputSchema: MCPToolInputSchema(properties: [
                "from_currency": MCPPropertySchema(type: "string", description: "From currency code"),
                "to_currency": MCPPropertySchema(type: "string", description: "To currency code"),
                "amount": MCPPropertySchema(type: "string", description: "Amount to convert")
            ], required: ["from_currency","to_currency"])
        )
    }
    
    private func getTranslationTool() -> MCPTool {
        return MCPTool(
            name: "translate_text",
            description: "Translate text to target language",
            inputSchema: MCPToolInputSchema(properties: [
                "text": MCPPropertySchema(type: "string", description: "Text to translate"),
                "target_language": MCPPropertySchema(type: "string", description: "Target language code"),
                "source_language": MCPPropertySchema(type: "string", description: "Source language code (optional)")
            ], required: ["text","target_language"])
        )
    }
    
    // Removed: check_travel_requirements (not supported)
    
    // MARK: - Implementations (stubbed to match legacy behavior)
    
    private func executeGetWeather(_ request: MCPCallToolRequest) async -> MCPCallToolResponse {
        let currentLocation = await MainActor.run { locationManager?.currentLocation }
        guard let loc = currentLocation else {
            return MCPCallToolResponse(content: [MCPContent(text: "Location not available")], isError: true)
        }
        guard let weather = weatherService else {
            return MCPCallToolResponse(content: [MCPContent(text: "Weather service unavailable")], isError: true)
        }
        do {
            let summary = try await weather.getCurrentWeather(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude)
            return MCPCallToolResponse(content: [MCPContent(text: summary)], isError: false)
        } catch {
            return MCPCallToolResponse(content: [MCPContent(text: error.localizedDescription)], isError: true)
        }
    }
    
    private func executeCurrency(_ request: MCPCallToolRequest) async -> MCPCallToolResponse {
        guard let from = request.arguments?["from_currency"] as? String,
              let to = request.arguments?["to_currency"] as? String else {
            return MCPCallToolResponse(content: [MCPContent(text: "Missing currency parameters")], isError: true)
        }
        let amount = Double((request.arguments?["amount"] as? String) ?? "1") ?? 1.0
        guard let fx = currencyService else {
            return MCPCallToolResponse(content: [MCPContent(text: "Currency service unavailable")], isError: true)
        }
        do {
            let (result, rate) = try await fx.convert(amount: amount, from: from, to: to)
            let text = "\(amount) \(from.uppercased()) = \(String(format: "%.2f", result)) \(to.uppercased()) (Rate: \(String(format: "%.4f", rate)))"
            return MCPCallToolResponse(content: [MCPContent(text: text)], isError: false)
        } catch {
            return MCPCallToolResponse(content: [MCPContent(text: error.localizedDescription)], isError: true)
        }
    }
    
    private func executeTranslate(_ request: MCPCallToolRequest) async -> MCPCallToolResponse {
        guard let text = request.arguments?["text"] as? String,
              let target = request.arguments?["target_language"] as? String else {
            return MCPCallToolResponse(content: [MCPContent(text: "Missing translation parameters")], isError: true)
        }
        let source = request.arguments?["source_language"] as? String
        guard let translator = translationService else {
            return MCPCallToolResponse(content: [MCPContent(text: "Translation service unavailable")], isError: true)
        }
        do {
            let out = try await translator.translate(text: text, to: target, source: source)
            return MCPCallToolResponse(content: [MCPContent(text: out)], isError: false)
        } catch {
            return MCPCallToolResponse(content: [MCPContent(text: error.localizedDescription)], isError: true)
        }
    }
    
    // Removed: executeTravelRequirements (not supported)
}

