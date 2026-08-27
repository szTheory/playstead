# Locked out? Recovering owner access without email

Playstead never sends email (D-02). If you're locked out of the console, there are two
email-free ways back in.

## 1. The host command (works even if you've lost your password entirely)

If you have shell access to the machine running Playstead (which you do — you're
self-hosting it), run:

```
docker compose exec app bin/playstead eval 'Playstead.Release.reset_owner_password()'
```

This prints a single-use, short-lived reset URL to the terminal. Visiting it once lets
you set a new password; visiting it again (or after it expires) is rejected.

**Running this command immediately ends every existing browser session for the owner
account.** That's deliberate — if someone else had a live session, it dies the moment
you reset the password, so a stolen session can never run alongside a fresh reset.

Host access is the root of trust here — the same principle that governs the initial
setup token printed at first boot. Anyone with shell access to the container can already
read and modify everything the application can; a password reset command doesn't create
a new privilege, it just gives the legitimate operator an email-free way to use the
privilege they already have.

## 2. A recovery code

At setup, you were shown ten single-use recovery codes. If you saved them somewhere
safe, you can log in with one directly at `/log-in/recovery` instead of your password.
Each code works exactly once; once used (or if you regenerate the set from the console),
it's permanently spent.

Recovery-code submissions are rate-limited on the same fixed per-IP and per-account
limits as ordinary password login — there is no adaptive lockout, so a self-hoster can
never accidentally lock themselves out by trying a code a few times.

## If you have neither

If you never saved a recovery code and don't have shell access to the host, there is no
email-based fallback — that's the tradeoff of a private, email-free server. Host access
is the root of trust for both bootstrap and recovery; without it, or without a saved
recovery code, the account cannot be recovered.
