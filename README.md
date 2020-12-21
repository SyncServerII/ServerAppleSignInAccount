# ServerAppleSignInAccount

The SyncServerII server uses plugins conforming to the [Account protocol](https://github.com/SyncServerII/ServerAccount.git) to provide server-side facilities for specific account types.

This specific plugin provides server-side facilities for Apple Sign In accounts.

This expects HTTP header keys:

`ServerConstants.HTTPOAuth2AuthorizationCodeKey`
and
`ServerConstants.HTTPOAuth2AccessTokenKey` (for the Apple Id token)
