# Releasing to the stores

The release button ([releasing the APK](releasing-the-apk.md)) builds for three places at once: the APK at `/download/android`, Google Play's closed testing track, and TestFlight. Promoting a build to the public store listings is done by hand, in each store's console. [ADR 0028](../adr/0028-wird-ships-through-play-and-the-app-store-beside-the-apk.md) records why it works this way.

```mermaid
flowchart LR
  button["release-app<br/>(the button)"] --> apk["apk job<br/>arm64 APK, 2000+N"]
  button --> aab["aab job<br/>app bundle, 2000+N"]
  button --> ipa["ipa.yml<br/>archive, build N"]
  apk --> site["/download/android"]
  aab --> closed["Play closed testing"]
  ipa --> tf["TestFlight"]
  closed -->|"promote by hand"| play["Play production"]
  tf -->|"submit by hand"| store["App Store"]
```

The `aab` job only runs once the repository variable `PLAY_RELEASE_ENABLED` is `true`, and `ipa.yml` only runs once `IOS_RELEASE_ENABLED` is `true`. Until then a release only builds the APK, exactly as before.

## One-time setup: Google Play

Do the steps in this order. Each step needs the one before it.

1. Create the developer account (personal) and confirm your identity. Then create the app with package name `dev.bnei.wird`, and complete developer verification for that package name with the APK's signing certificate.
2. **App signing.** In *Test and release → App integrity*, choose to use your own key and download Google's encryption public key. Commit it at `app/android/play-encryption-public-key.pem`. It is a public key, so it is safe to commit. Then run **apk** by hand from `main` with **pepk** ticked. The job produces `play-app-signing-key`, a zip encrypted to Google. Upload that zip in the Console. Play now signs with the same key as the APK.
3. **Upload key.** Generate a new keystore (RSA, 2048 bits or more) and store it in Infisical next to the release keystore, under the upload key names the `aab` job reads. Register its certificate in the Console as the upload key.
4. **First release, by hand.** Set `PLAY_RELEASE_ENABLED` to `true` and cut a release. The Play upload step fails the first time, because Play only accepts an app's first release from the Console. Download the `wird-aab` artifact from that run and upload it to the closed testing track in the Console.
5. **Service account.** Create one in Google Cloud and give it release permission on the app in the Play Console. Store its JSON key in Infisical. From now on the `aab` job uploads every release to the closed track by itself.
6. **Closed test.** Add at least 12 testers and keep the test running for 14 days. A new personal account cannot apply for production before that. This is the longest wait, so start it as early as you can.
7. Fill in the listing, Data safety, content rating and app access forms from the answers below. Then apply for production.

## One-time setup: App Store

1. In the developer portal, check that the App ID `dev.bnei.wird` has **Associated Domains** turned on. Xcode turns it on the first time it signs a build with the entitlement.
2. In App Store Connect, create the app with bundle ID `dev.bnei.wird`, primary language English, and SKU `wird`.
3. Create an App Store Connect API key with the **Admin** role. Cloud signing needs Admin; App Manager is not enough. Store the key file, its ID and the issuer ID in Infisical, under the identity that `ipa.yml` uses. That identity is separate from the one the APK uses, and it is set up in infra-bootstrap. Put its identity ID and project slug in the repository variables `ipa.yml` reads.
4. Set `IOS_RELEASE_ENABLED` to `true`. The next release appears in TestFlight once Apple has processed it.
5. Complete the EU trader declaration in App Store Connect. Google Play asks for the same declaration. Declaring yourself a trader makes your address and phone number public on the listing.
6. Fill in the listing, App Privacy, age rating and review notes from the answers below, then submit.

## The listing

| Field | Text |
|---|---|
| Name | Wird |
| Subtitle (App Store, 30) | Understand what you recite |
| Short description (Play, 80) | Read the Qur'an word by word, through its roots, and pray with it in front of you. |
| Category | Books (App Store: Reference) |
| Keywords (App Store, 100) | quran,koran,arabic,roots,salah,prayer,recitation,tajweed,word by word,morphology,tafsir |
| Support URL | the repository's GitHub issues page |
| Privacy policy URL | `https://wird.bnei.dev/privacy.html` |
| Price | Free, no in-app purchases, no ads |

**Full description**

> Wird helps you understand the ayas you recite in prayer.
>
> Pick a set of ayas and read it word by word. Every word opens into its root: the three letters it grows from, the other words that share them, and what the root means. When you pray, the set stays in front of you, and Wird can follow your recitation and keep your place.
>
> - Word-by-word glosses in English and French, with a translation of each aya.
> - Roots, forms and grammatical parsing for every word, from the Quranic Arabic Corpus.
> - Six reciters, with each word highlighted as it is recited, or each word spoken on its own.
> - Voice-follow: Wird listens while you recite and keeps your place. Your voice is processed on your phone and never leaves it.
> - Works offline, with no account. Sign in only if you want your reading on several devices.
>
> Wird is free and open source, with no ads and no tracking.

A French listing uses the same structure. The app's own French strings, in `app/lib/l10n/app_fr.arb`, are the reference for wording.

## Privacy forms

Both forms must say the same thing as [the privacy page](https://wird.bnei.dev/privacy.html). When one of them changes, change all three together.

| Data | Collected | Linked to the user | Why | Optional |
|---|---|---|---|---|
| User ID (account identifier) | yes, when signed in | yes | app functionality (sync) | yes |
| Other user content (notes, kept items, progress, prayers recorded) | yes, when signed in | yes | app functionality (sync) | yes |
| Customer support (bug reports) | yes, when the reader sends one | no | app functionality | yes |
| Audio (microphone) | **no**: processed on the device, never sent | | | |
| Location, contacts, identifiers for ads, diagnostics, usage data | no | | | |

Answers that apply to both stores:
- Data is encrypted in transit: yes.
- Tracking: none.
- Data is sold or shared with third parties: no.
- Users can request deletion: yes, in the app and by email.

On Play, Data safety also asks for an account deletion URL: use `https://wird.bnei.dev/privacy.html#deleting-your-account`.

The iOS privacy manifest, `app/ios/Runner/PrivacyInfo.xcprivacy`, declares the same three data types.

## Content rating and review notes

- **Rating.** Answer no to every content question. Wird is a reading app with no user-to-user communication and no web browsing.
- **App access.** Every feature works without signing in. Sign-in only syncs reading between devices.
- **Note for Apple review:**

  > No account is needed to use Wird. Sign-in is optional and only syncs reading between devices. To test account deletion, sign in with the demo account below, then go to Settings → Account → Delete account. The microphone is used for voice-follow during recitation; audio is processed on the device and never sent.

  Give a demo account from the identity provider in the review notes. A deletion removes Wird's data but not the sign-in itself, so the same demo account keeps working for the next review.

## Screenshots

| Store | Size | How many |
|---|---|---|
| Play, phone | 1080 × 1920 (no wider than 1:2), 24-bit PNG with no alpha | 2 to 8 |
| Play | feature graphic 1024 × 500, icon 512 × 512 | 1 each |
| App Store, iPhone 6.9" | 1320 × 2868 | 3 to 10 |
| App Store, iPad 13" | 2064 × 2752 | 3 to 10 |

The phone captures in `screens/` are 1080 × 2400 and include alpha. Both stores refuse them as they are: crop them to 1080 × 1920 and flatten the alpha first. The iPhone 16 used for testing is a 6.1" phone, which is the wrong size for the 6.9" slot. Capture the iPhone and iPad sizes from simulators instead:

```sh
scripts/store-screens.sh "iPhone 17 Pro Max" out/iphone      # 1320 × 2868
scripts/store-screens.sh "iPad Pro 13-inch (M5)" out/ipad    # 2064 × 2752
```

Each run uses a simulator of its own, sets the status bar to 9:41 with a full battery, hides the debug banner, and walks the screens in `app/integration_test/store_screens.dart`. On iPad, the home and prayer preparation screens are phone layouts stretched wide, so the iPad listing uses the set, the root, the deep dive and the prayer.

## Moving between the APK and Play

Play re-signs with the APK's own key and uses the APK's version code, so a phone that has one can install the other's next release as an ordinary update. A build with the same code shows as already installed. Check this once on a tester's phone during the closed test, in both directions, before telling APK users that they can switch.

> pending: the result of that check.
