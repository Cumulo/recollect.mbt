#!/usr/bin/env node
/**
 * Generate benchmark fixture JSON files for the chat-room diff/patch benchmark.
 *
 * Scenario: multi-user chat with channels, threads, and replies.
 * Output files (written relative to this script's directory):
 *   fixtures/state_base.json       – baseline snapshot
 *   fixtures/state_single_msg.json – one new message added to one thread
 *   fixtures/state_bulk_status.json – 30 % of users change online status
 *   fixtures/state_new_thread.json  – a new thread with 15 replies inserted
 *   fixtures/state_reorder.json     – threads within one channel are sorted differently
 */

import { writeFileSync, mkdirSync } from "fs";
import { fileURLToPath } from "url";
import { dirname, join } from "path";

const DIR = join(dirname(fileURLToPath(import.meta.url)), "fixtures");
mkdirSync(DIR, { recursive: true });

const RNG_SEED = 42;
let rng = RNG_SEED;
function rand() {
  rng = (rng * 1664525 + 1013904223) & 0xffffffff;
  return (rng >>> 0) / 0xffffffff;
}
function randInt(n) {
  return Math.floor(rand() * n);
}
function pick(arr) {
  return arr[randInt(arr.length)];
}
function uid(prefix, n) {
  return `${prefix}-${String(n).padStart(4, "0")}`;
}

const WORDS = [
  "alpha",
  "beta",
  "gamma",
  "delta",
  "echo",
  "foxtrot",
  "gulf",
  "hotel",
  "india",
  "juliet",
  "kilo",
  "lima",
  "mike",
  "november",
  "oscar",
  "papa",
  "quebec",
  "romeo",
  "sierra",
  "tango",
  "uniform",
  "victor",
  "whiskey",
  "xray",
  "yankee",
  "zulu",
  "sync",
  "diff",
  "patch",
  "state",
  "event",
  "signal",
  "stream",
  "channel",
  "thread",
  "reply",
  "post",
  "topic",
  "board",
  "room",
  "session",
  "token",
  "auth",
  "user",
];

function sentence(len = 8) {
  const words = [];
  for (let i = 0; i < len; i++) words.push(pick(WORDS));
  return words.join(" ");
}

const REACTIONS = ["👍", "❤️", "😂", "🎉", "🤔", "👀"];

// ── Users ────────────────────────────────────────────────────────────────────
const NUM_USERS = 50;
const users = Array.from({ length: NUM_USERS }, (_, i) => ({
  id: uid("user", i),
  name: `User ${i}`,
  avatar: `https://avatars/${uid("user", i)}.png`,
  online: rand() > 0.4,
  bio: sentence(6),
  role: pick(["member", "member", "member", "moderator", "admin"]),
  joined_at: 1700000000 + randInt(10000000),
}));

// ── Channels ─────────────────────────────────────────────────────────────────
const NUM_CHANNELS = 10;
const NUM_THREADS_PER_CHANNEL = 20;
const NUM_REPLIES_PER_THREAD = 10;

function makeReply(threadId, idx) {
  const author = pick(users);
  return {
    id: uid(`reply-${threadId}`, idx),
    author_id: author.id,
    author_name: author.name,
    text: sentence(randInt(12) + 4),
    ts: 1700000000 + randInt(10000000),
    reactions: Array.from({ length: randInt(4) }, () => ({
      emoji: pick(REACTIONS),
      user_id: pick(users).id,
    })),
    edited: rand() > 0.85,
  };
}

function makeThread(channelId, idx) {
  const author = pick(users);
  const tid = uid(`thread-${channelId}`, idx);
  return {
    id: tid,
    author_id: author.id,
    author_name: author.name,
    title: sentence(5),
    text: sentence(randInt(20) + 8),
    ts: 1700000000 + randInt(10000000),
    pinned: rand() > 0.9,
    tags: Array.from({ length: randInt(3) }, () => pick(WORDS)),
    reactions: Array.from({ length: randInt(5) }, () => ({
      emoji: pick(REACTIONS),
      user_id: pick(users).id,
    })),
    replies: Array.from({ length: NUM_REPLIES_PER_THREAD }, (_, r) =>
      makeReply(tid, r),
    ),
  };
}

function makeChannel(idx) {
  const cid = uid("chan", idx);
  return {
    id: cid,
    name: `#${pick(WORDS)}-${idx}`,
    description: sentence(8),
    threads: Array.from({ length: NUM_THREADS_PER_CHANNEL }, (_, t) =>
      makeThread(cid, t),
    ),
  };
}

const channels = Array.from({ length: NUM_CHANNELS }, (_, i) => makeChannel(i));

// ── Base state ────────────────────────────────────────────────────────────────
const baseState = {
  meta: {
    version: 1,
    generated_at: 1746000000,
    description:
      "Chat-room benchmark fixture: 50 users, 10 channels, 20 threads each, 10 replies each",
  },
  users,
  channels,
};

writeFileSync(join(DIR, "state_base.json"), JSON.stringify(baseState, null, 2));
console.log("✓ state_base.json");

// ── Scenario A: single new message ───────────────────────────────────────────
function deepClone(x) {
  return JSON.parse(JSON.stringify(x));
}

const stateA = deepClone(baseState);
const targetChannel = stateA.channels[3];
const targetThread = targetChannel.threads[7];
const newAuthor = pick(users);
targetThread.replies.push({
  id: uid(`reply-${targetThread.id}`, targetThread.replies.length),
  author_id: newAuthor.id,
  author_name: newAuthor.name,
  text: "This is the newly added benchmark message.",
  ts: 1746100000,
  reactions: [],
  edited: false,
});
writeFileSync(
  join(DIR, "state_single_msg.json"),
  JSON.stringify(stateA, null, 2),
);
console.log("✓ state_single_msg.json");

// ── Scenario B: bulk status change (30% users flip online) ──────────────────
const stateB = deepClone(baseState);
let flipped = 0;
for (const u of stateB.users) {
  if (rand() > 0.7) {
    u.online = !u.online;
    flipped++;
  }
}
stateB.meta.version = 2;
writeFileSync(
  join(DIR, "state_bulk_status.json"),
  JSON.stringify(stateB, null, 2),
);
console.log(`✓ state_bulk_status.json  (flipped ${flipped} users)`);

// ── Scenario C: new thread with 15 replies ────────────────────────────────────
const stateC = deepClone(baseState);
const cid2 = stateC.channels[1].id;
const newTid = uid(`thread-${cid2}`, NUM_THREADS_PER_CHANNEL);
const newAuthor2 = pick(users);
stateC.channels[1].threads.unshift({
  id: newTid,
  author_id: newAuthor2.id,
  author_name: newAuthor2.name,
  title: "Hot new discussion: " + sentence(4),
  text: sentence(20),
  ts: 1746200000,
  pinned: false,
  tags: [pick(WORDS), pick(WORDS)],
  reactions: [],
  replies: Array.from({ length: 15 }, (_, r) => makeReply(newTid, r)),
});
writeFileSync(
  join(DIR, "state_new_thread.json"),
  JSON.stringify(stateC, null, 2),
);
console.log("✓ state_new_thread.json");

// ── Scenario D: reorder threads in one channel (sort by title) ───────────────
const stateD = deepClone(baseState);
stateD.channels[5].threads.sort((a, b) => a.title.localeCompare(b.title));
writeFileSync(join(DIR, "state_reorder.json"), JSON.stringify(stateD, null, 2));
console.log("✓ state_reorder.json");

console.log("\nAll fixtures written to", DIR);
