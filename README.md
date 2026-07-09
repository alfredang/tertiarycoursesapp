# Tertiary Courses SG

Native iPhone app for [tertiarycourses.com.sg](https://www.tertiarycourses.com.sg/) that lists WSQ courses, searches TGS-coded course runs, estimates course grants, and sends course enquiries.

[![Download on the App Store](https://tools.applemediaservices.com/api/badges/download-on-the-app-store/black/en-us?size=250x83)](https://apps.apple.com/app/tertiary-courses/id6787036413)

![iOS](https://img.shields.io/badge/iOS-17%2B-black)
![SwiftUI](https://img.shields.io/badge/SwiftUI-native-blue)
![XcodeGen](https://img.shields.io/badge/XcodeGen-project-green)
![App Store](https://img.shields.io/badge/App_Store-live-0D96F6?logo=apple&logoColor=white)

## About

Tertiary Courses SG is a SwiftUI iPhone app for browsing WSQ course runs from the Tertiary Infotech LMS/TMS API. The app only shows WSQ courses whose course code starts with `TGS`.

## Features

- WSQ course catalog backed by the LMS/TMS API
- Course search across code, title, category, delivery, funding tier, summary, and outcomes
- Grant calculator with nationality and date-of-birth inputs
- SkillsFuture claimable and WSQ funding estimates
- Course enquiry form via WhatsApp
- Feedback and About bottom tabs in the Tertiary Infotech house style

## Tech Stack

- SwiftUI
- iOS 17+
- XcodeGen
- URLSession

## API Configuration

The API settings are generated into `Info.plist` from `project.yml`:

- `TERTIARY_COURSES_API_BASE_URL`
- `TERTIARY_COURSES_LIST_RUNS_PATH`
- `TERTIARY_COURSES_GET_RUN_PATH`
- `TERTIARY_COURSES_API_KEY`

The API key is intentionally blank in source control. Configure it locally or in CI before release.

## Project Structure

```text
.
├── TertiaryCoursesApp/
│   ├── Info.plist
│   └── TertiaryCoursesApp.swift
├── project.yml
├── .claude/skills/
└── README.md
```

## Getting Started

```bash
xcodegen generate
xcodebuild -scheme TertiaryCourses -destination 'generic/platform=iOS Simulator' build
```

Open `TertiaryCourses.xcodeproj` in Xcode to run the app on an iPhone simulator or device.

## Deployment

This repository is configured as a native iOS app. GitHub Pages deployment is not applicable.

## Credits

Course data is provided by the Tertiary Infotech LMS/TMS API and official SkillsFuture/SSG funding references.
