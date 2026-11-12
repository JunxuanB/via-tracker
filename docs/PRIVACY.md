# Train Tracker Privacy Policy

Effective 12 November 2026

Train Tracker is an independent, open-source app for following train trips. It is not affiliated with VIA Rail Canada. This policy explains what the app and its server store.

## Summary

- No account, no sign-in, no ads, no analytics, no tracking across apps or websites.
- The app does not ask for or use your location, contacts, photos, microphone or camera.
- Your trips are stored on your device. To send you updates, our server also keeps the trips you are tracking and the push tokens for your device.

## What is stored

**On your device**

- The trips you save, your settings, and the most recent train data so the app works offline.
- A random installation ID and secret, kept in the iOS Keychain.

**On our server**

- The installation ID and a one-way hash of its secret. The ID is random; it is not your Apple ID, name, email, phone number or advertising identifier.
- Push tokens issued by Apple for notifications, Live Activities and widgets, if you allow them.
- The trips you are tracking: train number, service date, boarding and alighting stations, your planned departure and travel time to the station, the trip name if you typed one, and your preferred notification language.
- Short-lived technical logs that do not contain trip contents, tokens or credentials.

Requests to the server necessarily include your IP address. It is used for rate limiting and is not stored with your trips.

## Why

Only to provide the app: to keep trip times up to date, send the notifications you asked for, and update Live Activities and widgets.

## Sharing

We do not sell or share your data. Two service providers process it on our behalf:

- **Cloudflare** hosts the server and database.
- **Apple** delivers push notifications.

Train information comes from VIA Rail Canada's public train status data. Our server reads it; your device and your data are never sent to VIA Rail.

## How long

- A tracked trip is deleted from the server when you end tracking or delete the trip. Otherwise it expires automatically at the later of one day after its last scheduled arrival and one day after its most recent synchronization.
- An installation with no tracked trips is deleted after 90 days without activity.
- Uninstalling removes the app’s local container. Installation credentials in the iOS Keychain may persist across reinstallations. Server data expires as described above.

## Your choices

- Turn notifications or Live Activities off in iOS Settings at any time; the app keeps working.
- End tracking or delete a trip in the app to remove it from the server.
- To have everything linked to your installation removed immediately, use the contact form at <https://junxuanb.com/#contact>. Do not send tokens or credentials; we will ask for the short device code if needed.

## Children

The app is not directed at children and does not knowingly collect personal information from them.

## Changes

Changes to this policy are published in this file, with a new effective date.

## Contact

<https://junxuanb.com/#contact>
