# Blipper

A native SwiftUI iPhone app for reviewing your diabetes data from [Tidepool](https://www.tidepool.org).

Blipper goes beyond continuous glucose monitor (CGM) readings. Alongside your glucose trace it shows insulin (boluses, including closed-loop automatic doses, and basal rates), carbs, and fingerstick meter readings. It also includes trend reports covering 7 to 90 days, your devices' pump and CGM settings, and notes you can pin to a moment and review against the data around it. And it manages who you share your Tidepool data with and which device clouds feed into it.

It is not limited to your own data: Blipper can show accounts that other people share with you, and clinicians can pick a patient from their clinic's list.

> ## ⚠️ Not for treatment decisions
>
> **Blipper is an informational viewer only. It is not a medical device and has not been reviewed or cleared by any regulator.**
>
> Do not use it to make insulin dosing, food, or other treatment decisions. Always rely on your CGM receiver, pump, or clinician for that. Data may be delayed, incomplete, or displayed incorrectly.

## Screenshots

| Today | Trends | BG Log | Settings | Device detail |
| :---: | :---: | :---: | :---: | :---: |
| ![Today tab: glucose timeline with insulin, carbs, and basal](docs/screenshots/Today.png) | ![Trends tab: time in range, stats, and AGP](docs/screenshots/trends.png) | ![BG Log tab: meter readings by day](docs/screenshots/BG_Log.png) | ![Settings tab: account, devices, targets](docs/screenshots/settings.png) | ![Device detail: Omnipod 5 pump settings](docs/screenshots/op5.png) |

## Features

**Today** – a glucose timeline for any day, with a shaded 70–180 mg/dL target band.
- Tap or drag on the chart to scrub; the header shows the selected reading and time.
- Switch between 3 h, 6 h, 12 h, and 24 h windows and step between days.
- Insulin and carbs under the glucose chart: boluses as bars (closed-loop automatic boluses as thin ticks), carb entries along the top, and basal rate as a step chart colored by scheduled, temp, automated, or suspended.
- Fingerstick readings appear as hollow dots on the glucose chart; scrubbing shows the basal rate in effect and any nearby bolus, carbs, or fingerstick.
- Summary tiles for time in range, average, and reading count, bolus, basal, and carb totals, plus a five-band breakdown (very low, low, in range, high, very high).
- Auto-refreshes every 5 minutes, with pull-to-refresh.
- When you are viewing someone else's data, their name appears at the top with a button back to the account or patient list.

**BG Log** – blood glucose meter (fingerstick) readings over 7, 14, 30, or 90 days, grouped by day with count, average, and in-range summary. Step back and forward one whole period at a time, as in Trends.

**Most recent data** – when an account has no data today, Today, Trends, and BG Log open on the newest day that has some, and the forward arrow stops there. Today's chart ends at the newest record rather than at midnight. Each screen looks at its own kind of data (BG Log at meter readings, Trends at CGM, Today at any of it), and pull-to-refresh checks again in case more has arrived.

**Trends** – 7, 14, 30, or 90 day reports.
- Step back and forward one whole period at a time to review earlier stretches; switching the period length keeps the same last day.
- Time in range with change versus the period just before the one shown.
- Average, standard deviation, coefficient of variation, and glucose management indicator (GMI).
- Ambulatory glucose profile (AGP) with median and 25–75 / 5–95 percentile bands.
- Daily stacked range bars.

**Notes** – notes as in Tidepool Mobile, stored in your Tidepool account alongside the notes from Tidepool Web.
- Tap + to write a note and set the date and time it is about.
- Notes are listed newest first with their time, and the author when a care team member wrote them.
- Tap a note to open its glucose, insulin, carb, and basal graph, marked at the note's time; swipe the graph to see up to 7 hours before the note. Opening another note closes the one that was open. A new note opens its graph as soon as it is saved.

**Shared accounts** – for a login that other people share their Tidepool data with.
- After signing in, choose whose data to see: your own account or one shared with you.
- "Open this account by default" remembers the choice; turn it off and Blipper asks each time it opens.
- Switch at any time under Settings → Viewing, where you can also change the default.
- Sharing and Data Connections manage your own account, so they are hidden while you view someone else's.
- If a share is withdrawn, Blipper drops that account and returns to the chooser or to your own data.

**Clinic patients** – for a login that is a clinician in one or more Tidepool clinics.
- The chooser lists your clinics; pick one to see its patients with date of birth and MRN.
- Search by name, MRN, or date of birth. The search runs on Tidepool's side and the list loads 50 patients at a time, so a large clinic is never downloaded whole. Dates of birth match as `YYYY-MM-DD`; a date typed `M/D/YYYY` is rewritten for you.
- Tap a patient to view their data. The Patients button on Today goes back to that clinic's list.
- Patient names, dates of birth, and MRNs are held in memory only: nothing about a patient is saved to the device or written to logs, so Blipper asks again each time it opens.
- Notes are read-only for clinic patients.
- Sign-in is by Tidepool email and password. Clinician accounts with two-factor authentication or single sign-on are not supported yet.

**Settings** – your Tidepool account, devices that uploaded in the last 30 days with their latest pump and CGM settings, target thresholds, and app info.

**Sharing** (under Settings) – the same share flow as the Share page in Tidepool Web.
- Share with a clinic: enter the 12-digit share code, confirm the clinic name that comes back, choose whether the clinic may upload, and send the invite.
- Share with a care team member by email, with the same upload choice.
- See who is sharing and which invites are still pending, allow or remove upload permission, resend a care team invite, revoke an invite, remove a member, or leave a clinic.

**Data Connections** (under Settings) – the cloud-to-cloud connections Tidepool supports: Dexcom, twiist, and FreeStyle Libre (LibreView).
- Each provider shows its logo and connection status with the same wording as Tidepool Web: connected with the time of the last data, awaiting data, error, or not connected.
- Connect or Reconnect asks Tidepool for a one-time authorization link and opens the provider's own sign-in in an in-app Safari sheet. Tidepool completes the OAuth exchange on its side; when the sheet closes, the status refreshes.
- Disconnect revokes Tidepool's authorization with the provider. FreeStyle Libre also needs to be disconnected in the LibreView app, and the screen says so.

## Requirements

- Xcode 27 or later
- iOS 17.0 or later
- A Tidepool account with data, access to one that is shared with you, or a clinician account (email and password sign-in, without two-factor authentication)

## Getting started

1. Open `Blipper.xcodeproj` in Xcode.
2. Select your own development team under *Signing & Capabilities*. The app uses a Keychain access group entitlement, so it must be built signed.
3. Run on a simulator or device and sign in with your Tidepool email and password.

Your credentials are stored in the device Keychain and sent only to `api.tidepool.org` to fetch data, save notes, and manage sharing and data connections. If you choose a default account, its name is kept in the Keychain too; clinic patients are never stored. They are never written to logs or sent anywhere else. Connecting a data provider opens that provider's sign-in page in an in-app Safari view; Blipper never sees those credentials.

### Developing without an account

Two launch arguments are available in Debug builds (set them in the scheme's *Arguments Passed On Launch*):

| Argument | Effect |
| --- | --- |
| `-useMockData` | Skips login and uses a deterministic mock CGM trace. |
| `-initialTab today\|trends\|log\|notes\|settings` | Opens on the given tab. |
| `-openSharing` | Starts on the Sharing screen (use with `-initialTab settings`). |
| `-openShareInvite` | Also presents the share invite form. |
| `-openDataConnections` | Starts on the Data Connections screen (use with `-initialTab settings`). |
| `-openNewNote` | Starts with the new note form open (use with `-initialTab notes`). |
| `-openFirstNote` | Opens the newest note's graph once notes load (use with `-initialTab notes`). |

## Architecture

- `Models/` – `GlucoseReading`, range classification and statistics, AGP and daily aggregation, device and settings models.
- `Data/` – a protocol-based data layer. `GlucoseDataProvider`, `TherapyDataProvider` (bolus, basal, wizard, food, and smbg records), `DeviceInfoProvider`, `ShareProvider` (clinic and care team sharing), and `DataConnectionProvider` (Dexcom, twiist, and LibreView links), and `NoteProvider` (notes in Tidepool's message service) each have a mock implementation and a Tidepool one built on `TidepoolClient`. `CredentialStore` wraps the Keychain. `SessionStore` holds the login, the account being viewed (`ViewableAccount`), and the clinics and shared accounts to choose from; a provider reads another account by carrying its user ID as the session's subject.
- `Views/` – SwiftUI views using Swift Charts.
- View models are `@Observable` and `@MainActor`; the data layer is `nonisolated` and `Sendable`.

Diagnostic logging uses OSLog (subsystem `com.PickleTron.blipper`) and records counts and field names only, never glucose values or account details.

## License

[MIT](LICENSE)
