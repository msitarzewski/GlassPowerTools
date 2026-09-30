# Your library on all your devices

When you are signed in to iCloud, the hosts you add on one device appear on your others, and their passwords travel with them. A few things stay on the device where you set them. This page lists what syncs, what does not, and how to check that syncing is working.

## What syncs and what stays

| What | Where it goes |
|---|---|
| Hosts, their addresses, other names and collections | Your other devices, through your private iCloud database |
| Each service and its settings, other than secrets | Your other devices, with its host |
| Passwords, SSH key passphrases and private keys | Your other devices, through iCloud Keychain, encrypted so that only your devices can read them |
| SSH keys generated in the Secure Enclave | This device only |
| Services that sign in with a Secure Enclave key | This device only |
| The host for this device (**This Mac**, **This iPad**, **This iPhone** or **This Apple Vision Pro**) and its services | This device only |
| Favorites, **Recent**, and which service **Connect opens** | This device only |
| Window appearance (**Settings** ▸ **Appearance**) | This device only |

> [!NOTE]
> A service set to require authentication keeps its password protected by this device's biometrics. That password cannot leave the device, so another device asks you for it again.

## When the library syncs

The library syncs when the app opens, when you return to it, and when iCloud reports a change made on another device.

- **On Vision Pro, iPad and iPhone:** pull the host list down to sync now.
- **On Mac:** there is no pull-down gesture. The library syncs at the times above.

If you are not signed in to iCloud, or iCloud is unavailable, the library on this device keeps working on its own. Nothing is lost; it syncs the next time iCloud is available.

## Check the sync status

The foot of the library's sidebar shows the iCloud status, for example **Synced with iCloud** and a time. Choose it (**on Vision Pro**, the cloud) for the details: when the last sync finished, how many records are in iCloud and how many were received and sent, and **Sync Now**.

Settings shows the same status:

1. Open **Settings** and choose **Privacy**.
2. Under **On your other devices**, read **Host library**:
   - **Synced** followed by a time: the last sync finished then.
   - **Syncing…**: a sync is running.
   - **Waiting to sync**: no sync has finished since the app opened.
   - **Not synced —** followed by a reason: the last attempt failed. The library on this device is unchanged.

## When two devices disagree

- If you edit the same host on two devices, the most recent edit wins for the whole host.
- If you delete a host on one device, it is deleted on the others, together with its services' saved settings and passwords. A deletion is final: an edit made on another device, even a later one, does not bring the host back.
- If two devices each set up the same machine, with the same name and the same address, the two are combined into one host the next time the library syncs. Where both have a service of the same kind and name, one is kept.

> [!TIP]
> If a host shows several addresses under **Address**, its records disagree about where the machine is. Edit the host and save one address to combine them.
