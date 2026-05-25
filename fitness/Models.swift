// Models.swift
import SwiftUI

extension Color {
    static let bg     = Color(red:0.05,green:0.05,blue:0.10)
    static let card   = Color(red:0.11,green:0.11,blue:0.17)
    static let accent = Color(red:0.53,green:0.40,blue:1.00)
    static let teal   = Color(red:0.06,green:0.73,blue:0.51)
    static let amber  = Color(red:0.96,green:0.62,blue:0.04)
}

enum Difficulty: String, CaseIterable, Codable {
    case beginner="Beginner", intermediate="Intermediate", advanced="Advanced"
    var color: Color {
        switch self {
        case .beginner:     return .teal
        case .intermediate: return .amber
        case .advanced:     return .red
        }
    }
}
enum Goal: String, CaseIterable, Codable {
    case weightLoss="Weight Loss", muscleGain="Muscle Gain"
    case endurance="Endurance",   general="General Fitness"
}

struct Exercise: Identifiable, Codable {
    var id = UUID(); var name: String; var sets: Int; var reps: Int
    var icon: String; var isCompleted: Bool = false

    /// Returns the trackable exercise type if camera tracking is supported for this exercise.
    var trackableExercise: TrackableExercise? {
        TrackableExercise.from(name: name)
    }

    /// True when this exercise can be tracked via the camera pose detector.
    var isTrackable: Bool { trackableExercise != nil }
}
struct WorkoutDay: Identifiable, Codable {
    var id = UUID(); var name: String; var focus: String
    var exercises: [Exercise]; var isRest: Bool; var duration: Int
    var completedDate: Date? = nil
    var isCompleted: Bool { completedDate != nil }
}
struct FitnessPlan: Identifiable, Codable {
    var id = UUID(); var name: String; var desc: String
    var difficulty: Difficulty; var weeks: Int; var goal: Goal
    var days: [WorkoutDay]; var emoji: String
}


extension FitnessPlan {
    static let defaults: [FitnessPlan] = [
        FitnessPlan(
            name:"Beginner Full Body", desc:"Build foundational strength in 4 weeks.",
            difficulty:.beginner, weeks:4, goal:.general, days:[
                WorkoutDay(name:"Mon", focus:"Full Body", exercises:[
                    Exercise(name:"Squat",         sets:3,reps:10,icon:"figure.strengthtraining.traditional"),
                    Exercise(name:"Push-Up",       sets:3,reps:12,icon:"figure.arms.open"),
                    Exercise(name:"Plank 30s",     sets:3,reps:1, icon:"figure.core.training"),
                ], isRest:false, duration:30),
                WorkoutDay(name:"Tue",focus:"Rest",   exercises:[],isRest:true, duration:0),
                WorkoutDay(name:"Wed",focus:"Cardio", exercises:[
                    Exercise(name:"Brisk Walk",    sets:1,reps:1, icon:"figure.walk"),
                    Exercise(name:"Jump Rope",     sets:3,reps:50,icon:"figure.jumprope"),
                ], isRest:false, duration:25),
                WorkoutDay(name:"Thu",focus:"Rest",   exercises:[],isRest:true, duration:0),
                WorkoutDay(name:"Fri",focus:"Upper Body", exercises:[
                    Exercise(name:"DB Row",        sets:3,reps:10,icon:"dumbbell.fill"),
                    Exercise(name:"Shoulder Press",sets:3,reps:10,icon:"figure.strengthtraining.functional"),
                ], isRest:false, duration:30),
                WorkoutDay(name:"Sat",focus:"Rest",exercises:[],isRest:true,duration:0),
                WorkoutDay(name:"Sun",focus:"Rest",exercises:[],isRest:true,duration:0),
            ], emoji:"🌱"),
        FitnessPlan(
            name:"Muscle Builder", desc:"6-week hypertrophy split.",
            difficulty:.intermediate, weeks:6, goal:.muscleGain, days:[
                WorkoutDay(name:"Mon",focus:"Chest & Triceps", exercises:[
                    Exercise(name:"Bench Press",   sets:4,reps:8, icon:"dumbbell.fill"),
                    Exercise(name:"Incline DB",    sets:3,reps:10,icon:"figure.strengthtraining.traditional"),
                    Exercise(name:"Tricep Dips",   sets:3,reps:12,icon:"figure.arms.open"),
                ], isRest:false, duration:45),
                WorkoutDay(name:"Tue",focus:"Back & Biceps", exercises:[
                    Exercise(name:"Pull-Up",       sets:4,reps:6, icon:"figure.arms.open"),
                    Exercise(name:"BB Row",        sets:4,reps:8, icon:"dumbbell.fill"),
                    Exercise(name:"Bicep Curl",    sets:3,reps:12,icon:"figure.strengthtraining.functional"),
                ], isRest:false, duration:45),
                WorkoutDay(name:"Wed",focus:"Rest",exercises:[],isRest:true,duration:0),
                WorkoutDay(name:"Thu",focus:"Legs", exercises:[
                    Exercise(name:"BB Squat",      sets:4,reps:8, icon:"figure.strengthtraining.traditional"),
                    Exercise(name:"Romanian DL",   sets:3,reps:10,icon:"dumbbell.fill"),
                ], isRest:false, duration:50),
                WorkoutDay(name:"Fri",focus:"Shoulders", exercises:[
                    Exercise(name:"OHP",           sets:4,reps:8, icon:"dumbbell.fill"),
                    Exercise(name:"Lateral Raise", sets:3,reps:15,icon:"figure.arms.open"),
                ], isRest:false, duration:40),
                WorkoutDay(name:"Sat",focus:"Cardio", exercises:[
                    Exercise(name:"HIIT Run",      sets:1,reps:1, icon:"figure.run"),
                ], isRest:false, duration:25),
                WorkoutDay(name:"Sun",focus:"Rest",exercises:[],isRest:true,duration:0),
            ], emoji:"💪"),
        FitnessPlan(
            name:"Fat Burn HIIT", desc:"High-intensity 4-week shred.",
            difficulty:.advanced, weeks:4, goal:.weightLoss, days:[
                WorkoutDay(name:"Mon",focus:"HIIT", exercises:[
                    Exercise(name:"Burpees",       sets:5,reps:20,icon:"figure.highintensity.intervaltraining"),
                    Exercise(name:"Mt. Climbers",  sets:5,reps:30,icon:"figure.core.training"),
                    Exercise(name:"Box Jumps",     sets:4,reps:15,icon:"figure.jumprope"),
                ], isRest:false, duration:35),
                WorkoutDay(name:"Tue",focus:"Strength", exercises:[
                    Exercise(name:"Deadlift",      sets:5,reps:5, icon:"dumbbell.fill"),
                    Exercise(name:"Squat",         sets:5,reps:5, icon:"figure.strengthtraining.traditional"),
                ], isRest:false, duration:50),
                WorkoutDay(name:"Wed",focus:"Run 5k", exercises:[
                    Exercise(name:"5k Run",        sets:1,reps:1, icon:"figure.run"),
                ], isRest:false, duration:30),
                WorkoutDay(name:"Thu",focus:"HIIT", exercises:[
                    Exercise(name:"KB Swings",     sets:5,reps:20,icon:"dumbbell.fill"),
                    Exercise(name:"Jump Squats",   sets:4,reps:15,icon:"figure.strengthtraining.traditional"),
                ], isRest:false, duration:35),
                WorkoutDay(name:"Fri",focus:"Full Body", exercises:[
                    Exercise(name:"Clean & Press", sets:4,reps:8, icon:"figure.strengthtraining.functional"),
                    Exercise(name:"Pull-Up",       sets:4,reps:10,icon:"figure.arms.open"),
                ], isRest:false, duration:45),
                WorkoutDay(name:"Sat",focus:"Recovery", exercises:[
                    Exercise(name:"Yoga Flow",     sets:1,reps:1, icon:"figure.mind.and.body"),
                ], isRest:false, duration:30),
                WorkoutDay(name:"Sun",focus:"Rest",exercises:[],isRest:true,duration:0),
            ], emoji:"🔥"),
    ]
}
