import SwiftUI

struct ExerciseLibraryView: View {
    @State private var searchText = ""
    @State private var selectedCategory: WgerCategoryFilter? = nil
    @State private var selectedEquipment: WgerEquipmentFilter? = nil
    
    @State private var exercises: [WgerExercise] = []
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var tutorialExerciseName: String? = nil
    
    // Wger category IDs mapped to friendly names
    enum WgerCategoryFilter: Int, CaseIterable, Identifiable {
        case arms = 8, legs = 9, abs = 10, chest = 11, back = 12, shoulders = 13, calves = 14, cardio = 15
        var id: Int { rawValue }
        var label: String {
            switch self {
            case .arms: return "Arms"
            case .legs: return "Legs"
            case .abs: return "Abs"
            case .chest: return "Chest"
            case .back: return "Back"
            case .shoulders: return "Shoulders"
            case .calves: return "Calves"
            case .cardio: return "Cardio"
            }
        }
    }
    
    // Wger equipment IDs mapped to friendly names
    enum WgerEquipmentFilter: Int, CaseIterable, Identifiable {
        case barbell = 1, dumbbell = 3, gym = 4, pullUpBar = 6, bodyweight = 7, bench = 8, kettlebell = 10
        var id: Int { rawValue }
        var label: String {
            switch self {
            case .barbell: return "Barbell"
            case .dumbbell: return "Dumbbell"
            case .gym: return "Gym Machine"
            case .pullUpBar: return "Pull-up Bar"
            case .bodyweight: return "Bodyweight"
            case .bench: return "Bench"
            case .kettlebell: return "Kettlebell"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    searchAndFilterSection
                    
                    if isLoading {
                        Spacer()
                        ProgressView("Searching Wger...").tint(.teal).foregroundColor(.secondary)
                        Spacer()
                    } else if let error = errorMessage {
                        Spacer()
                        VStack {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.largeTitle).foregroundColor(.amber).padding(.bottom, 4)
                            Text(error).foregroundColor(.secondary).multilineTextAlignment(.center)
                        }.padding()
                        Spacer()
                    } else if exercises.isEmpty {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 48)).foregroundColor(.secondary)
                            Text("No exercises found")
                                .font(.headline).foregroundColor(.white)
                            Text("Try adjusting your filters or search term.")
                                .font(.subheadline).foregroundColor(.secondary)
                        }
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(exercises) { ex in
                                    ExerciseLibraryCard(exercise: ex) {
                                        tutorialExerciseName = ex.name
                                    }
                                }
                            }
                            .padding()
                        }
                    }
                }
            }
            .navigationTitle("Library")
            .sheet(item: Binding(
                get: { tutorialExerciseName.map { TutorialItem(name: $0) } },
                set: { tutorialExerciseName = $0?.name }
            )) { item in
                ExerciseTutorialView(exerciseName: item.name)
            }
            .task {
                if exercises.isEmpty {
                    await search()
                }
            }
        }
    }
    
    var searchAndFilterSection: some View {
        VStack(spacing: 12) {
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Search exercises (e.g. squat, curl)...", text: $searchText)
                    .foregroundColor(.white)
                    .submitLabel(.search)
                    .onSubmit {
                        Task { await search() }
                    }
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        Task { await search() }
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color.card)
            .cornerRadius(10)
            .padding(.horizontal)
            
            // Filters
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Menu {
                        Button("Any Category") { selectedCategory = nil; Task { await search() } }
                        Divider()
                        ForEach(WgerCategoryFilter.allCases) { cat in
                            Button(cat.label) {
                                selectedCategory = cat; Task { await search() }
                            }
                        }
                    } label: {
                        FilterChip(title: selectedCategory?.label ?? "Category", isSelected: selectedCategory != nil)
                    }
                    
                    Menu {
                        Button("Any Equipment") { selectedEquipment = nil; Task { await search() } }
                        Divider()
                        ForEach(WgerEquipmentFilter.allCases) { eq in
                            Button(eq.label) {
                                selectedEquipment = eq; Task { await search() }
                            }
                        }
                    } label: {
                        FilterChip(title: selectedEquipment?.label ?? "Equipment", isSelected: selectedEquipment != nil)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 8)
        }
        .padding(.top, 8)
        .background(Color.bg)
    }
    
    private func search() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let service = WgerService()
            let results = try await service.searchExercises(
                name: searchText.isEmpty ? nil : searchText,
                category: selectedCategory?.rawValue,
                equipment: selectedEquipment?.rawValue
            )
            await MainActor.run {
                self.exercises = results
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    
    var body: some View {
        HStack {
            Text(title)
            Image(systemName: "chevron.down").font(.caption2)
        }
        .font(.caption.bold())
        .foregroundColor(isSelected ? .bg : .white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accent : Color.card)
        .cornerRadius(16)
    }
}

struct ExerciseLibraryCard: View {
    let exercise: WgerExercise
    let onTutorialTap: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let url = exercise.imageUrl {
                CachedAsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 140)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .cornerRadius(8)
                } placeholder: {
                    Color.black.opacity(0.1)
                        .frame(height: 140)
                        .cornerRadius(8)
                        .overlay(Image(systemName: "photo").foregroundColor(.secondary))
                }
                .padding(.bottom, 4)
            }
            
            HStack {
                Text(exercise.name)
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Button(action: onTutorialTap) {
                    HStack(spacing: 4) {
                        Image(systemName: "book.fill")
                        Text("Tutorial")
                    }
                    .font(.caption2.bold())
                    .foregroundColor(.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.accent.opacity(0.15))
                    .cornerRadius(8)
                }
            }
            
            HStack(spacing: 8) {
                if let cat = exercise.category {
                    Text(cat.name)
                        .font(.caption)
                        .foregroundColor(.teal)
                }
                if let muscles = exercise.muscles, !muscles.isEmpty {
                    Text("•")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text(muscles.map { $0.name }.joined(separator: ", "))
                        .font(.caption)
                        .foregroundColor(.accent)
                        .lineLimit(1)
                }
            }
            
            HStack(alignment: .top) {
                Image(systemName: "dumbbell.fill")
                    .foregroundColor(.secondary)
                    .font(.caption)
                    .frame(width: 16)
                Text(exercise.equipmentDisplay)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(Color.card)
        .cornerRadius(12)
    }
}


/// A simple singleton cache that saves images to the app's Caches directory.
class ImageCache {
    static let shared = ImageCache()
    private let cacheDirectory: URL
    
    init() {
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        cacheDirectory = paths[0].appendingPathComponent("WgerImageCache")
        if !FileManager.default.fileExists(atPath: cacheDirectory.path) {
            try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
    }
    
    private func fileUrl(for url: URL) -> URL {
        // Use a safe string for the filename
        let safeName = url.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? UUID().uuidString
        return cacheDirectory.appendingPathComponent(safeName)
    }
    
    func getImage(for url: URL) -> UIImage? {
        let file = fileUrl(for: url)
        if let data = try? Data(contentsOf: file), let image = UIImage(data: data) {
            return image
        }
        return nil
    }
    
    func saveImage(_ image: UIImage, for url: URL) {
        let file = fileUrl(for: url)
        // Store as JPEG to save space
        if let data = image.jpegData(compressionQuality: 0.8) {
            try? data.write(to: file)
        }
    }
}

/// A drop-in replacement for AsyncImage that permanently caches downloaded images.
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL
    let content: (Image) -> Content
    let placeholder: () -> Placeholder
    
    @State private var uiImage: UIImage? = nil
    @State private var isLoading = true
    @State private var hasError = false
    
    init(url: URL, @ViewBuilder content: @escaping (Image) -> Content, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
    }
    
    var body: some View {
        Group {
            if let uiImage = uiImage {
                content(Image(uiImage: uiImage))
            } else if hasError {
                placeholder()
            } else {
                placeholder()
                    .overlay(ProgressView())
            }
        }
        .task {
            await loadImage()
        }
    }
    
    private func loadImage() async {
        // 1. Check local disk cache first (Instant)
        if let cached = ImageCache.shared.getImage(for: url) {
            await MainActor.run {
                self.uiImage = cached
                self.isLoading = false
            }
            return
        }
        
        // 2. Download from network (Can be slow for Wger)
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 120 // Give Wger up to 2 minutes to respond
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
                  let downloadedImage = UIImage(data: data) else {
                await MainActor.run { self.hasError = true }
                return
            }
            
            // 3. Save to disk so it's fast next time
            ImageCache.shared.saveImage(downloadedImage, for: url)
            
            await MainActor.run {
                self.uiImage = downloadedImage
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.hasError = true
                self.isLoading = false
            }
        }
    }
}
