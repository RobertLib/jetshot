# Privacy Policy — Jetshot

*Last updated: November 3, 2026*

## In short

Jetshot collects no personal data. The only thing that ever leaves your device is
your own game progress, and it goes to your own iCloud account.

## In detail

**No data is collected.** The app never asks for your name, email address, phone
number or any other personal information. No account and no sign-in is required,
and nothing about you or your play is sent to me or to anyone else.

**No analytics, no advertising, no tracking.** The app contains no ad networks, no
analytics frameworks and no third-party SDKs of any kind. It links only Apple's
own frameworks. There is no advertising identifier and no tracking of any sort.

**No in-app purchases.** The app contains no in-app purchases and no
subscriptions.

**Where your progress is stored.** Completed levels, level scores, star ratings,
weapon loadouts, earned medals and your endless-run records are stored on your
device using the system UserDefaults store. A progress reset counter
(`progressEpoch`) and the time of the last reset (`progressResetAt`) are also
stored to prevent an older copy on another device from restoring erased
progress. The device additionally keeps the time its current progress began
(`progressStartedAt`), so that progress made after a reset is not mistaken for
progress from before it. That time stays on the device and is never synced.

**iCloud synchronization.** All the progress values above, including medals, the
reset counter and the reset time, are mirrored to Apple's iCloud Key-Value
Storage so that your progress follows you between your own devices and survives
reinstalling the app. Next to each progress value iCloud also holds a small
marker with the reset counter it was saved under (for example
`completedLevels.epoch`), so that a save from a device that had not yet received
a reset can be recognized and ignored. That data lives in your personal iCloud
account, is readable only on devices signed in with your Apple ID, and I have no
access to it — there is no server of mine involved at any point. With no iCloud
account signed in, the game works normally using local storage.

**Everything else runs offline.** All content — levels, graphics, music and sound
— ships inside the app. Apart from the iCloud sync above, the app makes no network
requests.

**Device access.** The app does not use the camera, microphone, location services,
contacts, health data or any other sensitive permission. It only uses haptic
feedback and audio playback.

**Children.** The app is suitable for all ages. Because it collects no data, no
data about children is created either.

**Deleting your data.** RESET on the level-select screen erases completed
levels, scores, star ratings, weapon loadouts, medals and endless records from
the device and from iCloud, together with their markers and the start time. The
reset counter is retained and incremented, and the time of the reset is recorded
with it, so that erased progress cannot return from another device. Deleting the
app removes the local copy; it does not by itself erase your progress in iCloud.

## Changes to this policy

Any changes will be posted on this page with an updated date.

## Contact

For privacy questions, contact: **libsansky@iquest.cz**
