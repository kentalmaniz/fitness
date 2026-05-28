import SwiftUI

struct ExerciseTutorialView: View {
    let exerciseName: String
    
    @Environment(\.dismiss) private var dismiss
    @State private var wgerExercise: WgerExercise?
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    
    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Exercise Tutorial")
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color.card)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(exerciseName)
                            .font(.largeTitle.bold())
                            .foregroundColor(.white)
                            .padding(.top)
                        
                        if isLoading {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .scaleEffect(1.5)
                                    .tint(.teal)
                                    .padding(40)
                                Spacer()
                            }
                        } else if let error = errorMessage {
                            VStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.largeTitle)
                                    .foregroundColor(.amber)
                                Text("Couldn't Load Details")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                Text(error)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(30)
                            .background(Color.card)
                            .cornerRadius(16)
                        } else if let ex = wgerExercise {
                            tutorialContent(for: ex)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 40)
                }
            }
        }
        .task {
            await fetchTutorial()
        }
    }
    
    private func tutorialContent(for ex: WgerExercise) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            
            if let url = ex.imageUrl {
                CachedAsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 300)
                        .cornerRadius(12)
                } placeholder: {
                    Color.black.opacity(0.1)
                        .frame(maxWidth: .infinity, minHeight: 200)
                        .cornerRadius(12)
                        .overlay(Image(systemName: "photo").foregroundColor(.secondary))
                }
            }
            
            // Badges Row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    if let category = ex.category {
                        badge(text: category.name, icon: "figure.run", color: .accent)
                    }
                    if let muscles = ex.muscles, !muscles.isEmpty {
                        badge(text: muscles.map { $0.name }.joined(separator: ", "),
                              icon: "figure.walk", color: .teal)
                    }
                }
            }
            
            // Equipment
            VStack(alignment: .leading, spacing: 8) {
                Label("Equipment", systemImage: "dumbbell.fill")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text(ex.equipmentDisplay)
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.card)
                    .cornerRadius(10)
            }
            
            // Instructions (from description)
            let instructions = ex.descriptionStr
            if !instructions.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Instructions", systemImage: "list.bullet.clipboard.fill")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Text(instructions)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .lineSpacing(4)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.card)
                        .cornerRadius(12)
                }
            }
            
            // Safety note (generic for Wger)
            VStack(alignment: .leading, spacing: 8) {
                Label("Safety Cues", systemImage: "exclamationmark.shield.fill")
                    .font(.headline)
                    .foregroundColor(.amber)
                
                Text("Scale range, speed, or load before form breaks. Stop immediately if you feel pain.")
                    .font(.subheadline)
                    .foregroundColor(.amber.opacity(0.9))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.amber.opacity(0.1))
                    .cornerRadius(10)
            }
            
            Spacer(minLength: 20)
        }
    }
    
    private func badge(text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption.bold())
        .foregroundColor(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.15))
        .cornerRadius(8)
    }
    
    private func fetchTutorial() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let service = WgerService()
            if let result = try await service.lookupExercise(name: exerciseName) {
                wgerExercise = result
            } else {
                errorMessage = "No detailed tutorial found for '\(exerciseName)'."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
}
