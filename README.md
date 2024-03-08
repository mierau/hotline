<img width="836" alt="hotline-image" src="https://github.com/mierau/hotline/assets/55453/c236a792-3ba6-4395-9d84-dcb113b7a267">

# Hotline
An attempt to ressurect Hotline for modern Apple systems (iOS, macOS, etc) by completely recreating it in Swift and SwiftUI.

[Download the Latest](https://github.com/mierau/hotline/releases/latest)

**Note:** This project (so far) does not include server software. This is a client for connecting to and participating on Hotline servers. If you would like to host your own Hotline server (and you should!), please checkout the very capable Mobius project: https://github.com/jhalter/mobius

# Requirements

| macOS                      | iOS                   | iPadOS            | visionOS          |
|----------------------------|-----------------------|-------------------|-------------------|
| Sonoma 14.2 or greater     | iOS 17.2 or greater   | Not yet available | Not yet available |

# What is Hotline?

Hotline was released in 1997 for Mac OS. A suite of three (free) applications that allowed people to join or host online communities directly from their Macs. No subscriptions. No ads.

When connected to a Hotline server you could chat with other users like IRC, message others privately like AIM, read or write threaded news like a forum, post to the server’s message board like BBS, and browse, upload, or download files like FTP. And as someone operating a Hotline server you had full control over all of it.

Hotline also included Trackers. Trackers tracked servers. If you ran a Hotline server, you could list it on one or more Trackers so people could find your server—and anyone could run a Tracker.

At a time when people were chatting over email and file sharing was passing physical media between friends, Hotline was a kind of revelation. The promise of the Internet, in a way. Computers owned by individuals, connected and passing information between each other. No central server that could take the entire network offline.

Perhaps that’s why you can still find Hotline servers and trackers running today 25 years later. Though the company who built Hotline is no longer around, and the software they made is only available through retro Mac software archives, these communities are still operating.

And this project is an attempt to create a modern open source version of Hotline for modern Apple systems. Join in. Contribute. Run your own server! Perhaps Hotline can live on for another 25 years. :)

# Status

| Feature                    | macOS | iOS   | iPadOS | visionOS |
|----------------------------|-------|-------|--------|----------|
| Trackers listing           |   ✓   |   ✓   |        |          |
| Multiple trackers          |   ✓   |       |        |          |
| Connect to servers         |   ✓   |   ✓   |        |          |
| Connect to multiple servers|   ✓   |       |        |          |
| Server accounts            |   ✓   |       |        |          |
| Server bookmarks           |   ✓   |       |        |          |
| Change name & icon         |   ✓   |       |        |          |
| Privacy settings           |   ✓   |       |        |          |
| Autoresponse               |   ✓   |       |        |          |
| Display server agreement   |   ✓   |   ✓   |        |          |
| Display server banner      |   ✓   |   ✓   |        |          |
| Public chat                |   ✓   |   ✓   |        |          |
| Private messages           |       |       |        |          |
| User list                  |   ✓   |   ✓   |        |          |
| User icons                 |   ✓   |   ✓   |        |          |
| User administration        |       |       |        |          |
| News reading               |   ✓   |   ✓   |        |          |
| News posting               |       |       |        |          |
| Message board reading      |   ✓   |   ✓   |        |          |
| Message board posting      |   ✓   |       |        |          |
| File browsing              |   ✓   |   ✓   |        |          |
| File downloading           |   ✓   |       |        |          |
| File uploading             |       |       |        |          |
| File info                  |       |       |        |          |
| File management            |       |       |        |          |
| Folder downloading         |       |       |        |          |
| Folder uploading           |       |       |        |          |
| Custom icon sets           |       |       |        |          |

# Goals
- Build a Hotline client for modern Apple systems.
- Keep the HotlineProtocol, HotlineClient, HotlineTrackerClient, and HotlineFileClient Swift code reusable so people can use it in other Swift Hotline projects.
- Bring a modern Hotline client to iOS, iPadOS, and macOS using one codebase.
- Ressurect the Hotline brand that has been expunged from trademark databases for over a decade. Hey, I want Hotline proper with the classic big red H and all on my modern Apple devices, okay? ;)
- Document the Hotline protocol.
- Have fun. :)

# macOS Screenshots
![CleanShot 2024-01-01 at 11 59 13@2x](https://github.com/mierau/hotline/assets/55453/b8cbad58-e1e2-4ff3-ba4b-fa3302c897ca)

# iOS Screenshots
![IMG_0658](https://github.com/mierau/hotline/assets/55453/8d9fd292-80b7-4c3a-b1a2-6311994ec8e7)
