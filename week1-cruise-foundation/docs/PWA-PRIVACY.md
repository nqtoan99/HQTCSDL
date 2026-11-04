# PWA and browser data policy

## App shell

The HTML shell in `public/index.html` is stored in an HTML `<template>` and mounted by the local React entry point in `public/app-root.js`. React and React DOM are served from `public/vendor`, so the initial interface does not depend on a third-party CDN. The existing application script continues to fill the page's data panels.

The web manifest provides standalone display metadata and 192 px / 512 px icons. The service worker pre-caches the app shell and handles only a fixed allowlist of same-origin shell paths. It bypasses every `/api/` request and does not cache arbitrary same-origin URLs.

## Private API responses

The server returns JSON and QR responses with `Cache-Control: no-store`. The service worker also ignores `/api/`, so private API responses are not put into Cache Storage.

POS receipts are fetched from the API into memory while the page is open. They are not written to `localStorage`; offline restoration starts with an empty receipt list. On startup, any older POS cache entries are rewritten without receipt rows or the staff member's name.

## Offline POS outbox

Pending POS entries remain in `localStorage` so they survive a reload and can be synchronized later. The outbox contains the locally entered booking code, service identifier/name, device identifier, quantity, timestamp, synchronization status, and idempotency UUID. It is separate from API read responses and is required for the offline POS workflow. Error details are replaced with a generic message before they are stored. The saved offline catalog contains service/device choices and a minimal POS user ID/role marker; it does not contain customer names, account balances, invoices, or receipts.

This browser storage is intended for the demo workflow on a trusted POS device. Clearing browser site data removes the local queue before it is synchronized.
