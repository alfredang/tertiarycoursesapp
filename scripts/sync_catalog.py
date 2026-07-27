#!/usr/bin/env python3
"""Sync the course catalog from tertiarycourses.com.sg into Courses.json.

The storefront exposes no public product API, so the catalog is rebuilt from the
site's own published data:

  * sitemap.xml lists every URL (product and category pages mixed together).
  * A page is a PRODUCT iff it carries a JSON-LD {"@type": "Course"} block. That
    block is the source for title, description, price (pre-GST) and workload.
  * The TGS course code and the funding-scheme badges (WSQ/SFC/SFEC/PSEA/UTAP/IBF)
    are read from the page markup, so eligibility is real data and never inferred.
  * Breadcrumbs carry no category, so category membership comes from the category
    pages themselves, fetched with ?limit=all (without it each returns only its
    first 20 products and the mapping silently comes out short).

Usage:
    python3 scripts/sync_catalog.py --out TertiaryCoursesApp/Courses.json
"""
from __future__ import annotations

import argparse
import collections
import concurrent.futures
import gzip
import html
import json
import re
import sys
import urllib.request

SITE = "https://www.tertiarycourses.com.sg"
SITEMAP = f"{SITE}/sitemap.xml"
UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/124 Safari/537.36")
WORKERS = 12

# Umbrella/funding/marketing categories that say nothing about the SUBJECT.
SKIP_CATEGORY = re.compile(
    r"^(adult courses|latest courses|wsq and ibf courses|wsq funded courses|software training|"
    r"certification exam prep|all courses|courses|new courses|promotion|featured|"
    r"skillsfuture courses|sfc courses|utap courses|ibf courses|psea courses|"
    r"wsq certification courses|infocomm technology|training courses.*)$", re.I)

# First match wins, so specific signals (CompTIA, ISO, Power Automate) must come
# BEFORE the broad "AI" pattern they would otherwise be swallowed by.
GROUPS = [
    ("Cybersecurity",           r"\b(comptia|cissp|cisa|cism|ethical hack|penetration|forensic|cyber ?security|secai)\b"),
    ("Microsoft Office",        r"\b(excel|word|powerpoint|outlook|microsoft 365|sharepoint|power automate|power apps|power platform|power bi)\b"),
    ("Quality & Compliance",    r"\b(iso \d|internal auditor|quality assurance|greenhouse gas|sustainab|esg|carbon)\b"),
    ("Artificial Intelligence", r"\b(ai|artificial intelligence|genai|generative|chatgpt|llm|agentic|machine learning|deep learning|prompt)\b"),
    ("Data & Analytics",        r"\b(data|analytics|analysis|visualisation|visualization|tableau|statistic|big data|sql|database)\b"),
    ("Programming",             r"\b(programming|python|java|javascript|c\+\+|c#|coding|developer|web development|app development|vibe coding|software development)\b"),
    ("Cloud & DevOps",          r"\b(cloud|aws|azure|devops|docker|kubernetes|linux|server|networking|network)\b"),
    # Generic security wording, after the named certs above and before the broader groups.
    ("Cybersecurity",           r"\b(security|cyber|pentest|threat|malware|firewall|encryption|privacy|compliance)\b"),
    ("Digital Marketing",       r"\b(marketing|seo|social media|advertis|e-commerce|ecommerce|content creation|copywriting)\b"),
    ("Design & Media",          r"\b(design|graphic|media|video|photo|adobe|photoshop|illustrator|premiere|animation|3d|blender|autodesk|drawing|cad)\b"),
    ("Business & Soft Skills",  r"\b(business|soft skill|critical core|leadership|management|project management|communication|presentation|finance|accounting|hr|human resource|productivity|service)\b"),
    ("Engineering & IoT",       r"\b(electronic|semiconductor|iot|arduino|raspberry|robotic|engineering|manufactur|mechatronic|plc)\b"),
]

ICONS = {
    "Artificial Intelligence": "sparkles",
    "Data & Analytics": "chart.xyaxis.line",
    "Programming": "chevron.left.forwardslash.chevron.right",
    "Cloud & DevOps": "cloud.fill",
    "Cybersecurity": "lock.shield.fill",
    "Digital Marketing": "megaphone.fill",
    "Design & Media": "paintbrush.fill",
    "Microsoft Office": "square.grid.2x2.fill",
    "Business & Soft Skills": "briefcase.fill",
    "Engineering & IoT": "cpu.fill",
    "Quality & Compliance": "checkmark.seal.fill",
    "Other Courses": "books.vertical.fill",
}


def fetch(url: str, tries: int = 3) -> str | None:
    for attempt in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept-Encoding": "gzip"})
            with urllib.request.urlopen(req, timeout=45) as resp:
                raw = resp.read()
            if raw[:2] == b"\x1f\x8b":
                raw = gzip.decompress(raw)
            return raw.decode("utf-8", "replace")
        except Exception:
            if attempt == tries - 1:
                return None
    return None


def text(value: str | None) -> str:
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", value or ""))).strip()


def parse_product(url: str, page: str | None) -> dict | None:
    """Return the course dict for a product page, or None for a category page."""
    if not page:
        return None

    course = None
    for block in re.findall(r'<script[^>]*application/ld\+json[^>]*>(.*?)</script>', page, re.S):
        try:
            data = json.loads(block.strip())
        except Exception:
            continue
        if isinstance(data, dict) and data.get("@type") == "Course":
            course = data
            break
    if not course:
        return None

    title = text(course.get("name"))
    if not title:
        return None

    offers = course.get("offers") or {}
    if isinstance(offers, list):
        offers = offers[0] if offers else {}
    try:
        price = float(str(offers.get("price", "0")).replace(",", ""))
    except Exception:
        price = 0.0

    instance = course.get("hasCourseInstance") or {}
    if isinstance(instance, list):
        instance = instance[0] if instance else {}
    hours = 0.0
    workload = re.match(r"PT(\d+(?:\.\d+)?)H", str(instance.get("courseWorkload") or ""))
    if workload:
        hours = float(workload.group(1))

    code = ""
    code_match = re.search(r'course-code-inline__value">\s*([A-Za-z0-9\-]+)\s*<', page)
    if code_match:
        code = code_match.group(1).strip()

    badges = {b.lower() for b in re.findall(r'course-badge course-badge--([a-z]+)"', page)}

    return {
        "url": url,
        "title": title,
        "summary": text(course.get("description")),
        "code": code,
        "price": price,
        "mode": text(instance.get("courseMode")) or "Classroom",
        "hours": hours,
        "badges": sorted(badges),
    }


def scan_category(url: str) -> tuple[str, list[str]] | None:
    """Return (category name, member product URLs) for a category page."""
    page = fetch(f"{url}?limit=all")
    if not page:
        return None
    heading = re.search(r"<h1[^>]*>(.*?)</h1>", page, re.S)
    name = text(heading.group(1)) if heading else ""
    if not name:
        return None
    members = set(re.findall(r'class="product-name"[^>]*>\s*<a[^>]*href="([^"]+)"', page))
    members |= set(re.findall(r'<h2 class="product-name"><a href="([^"]+)"', page))
    return name, sorted(m.split("?")[0] for m in members)


def group_for(name: str) -> str | None:
    for label, pattern in GROUPS:
        if re.search(pattern, name, re.I):
            return label
    return None


def duration_text(hours: float) -> str:
    """Site workload is in hours; show it in training days (a day is ~7-8 hours)."""
    if not hours:
        return "Check schedule"
    days = max(1, round(hours / 7.5))
    return f"{days} day{'' if days == 1 else 's'}"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True, help="path to write Courses.json")
    ap.add_argument("--min-courses", type=int, default=400,
                    help="fail if fewer courses than this are found (guards against a broken scrape)")
    args = ap.parse_args()

    sitemap = fetch(SITEMAP)
    if not sitemap:
        print("FATAL: could not fetch sitemap", file=sys.stderr)
        return 1
    urls = [u for u in re.findall(r"<loc>([^<]+)</loc>", sitemap) if u.endswith(".html")]
    print(f"sitemap: {len(urls)} urls", file=sys.stderr)

    # Pass 1 — every URL, keeping the ones that are product pages.
    products: list[dict] = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=WORKERS) as pool:
        futures = {pool.submit(lambda u: parse_product(u, fetch(u)), u): u for u in urls}
        for done, future in enumerate(concurrent.futures.as_completed(futures), 1):
            result = future.result()
            if result:
                products.append(result)
            if done % 200 == 0:
                print(f"  scanned {done}/{len(urls)} → {len(products)} products", file=sys.stderr)
    print(f"products: {len(products)}", file=sys.stderr)

    if len(products) < args.min_courses:
        print(f"FATAL: only {len(products)} courses found (expected >= {args.min_courses}). "
              "The site markup may have changed — refusing to publish a truncated catalog.",
              file=sys.stderr)
        return 1

    # Pass 2 — category pages, to learn which category each product belongs to.
    product_urls = {p["url"] for p in products}
    category_urls = [u for u in urls if u not in product_urls]
    candidates: dict[str, list[str]] = collections.defaultdict(list)
    with concurrent.futures.ThreadPoolExecutor(max_workers=WORKERS) as pool:
        for result in pool.map(scan_category, category_urls):
            if not result:
                continue
            name, members = result
            if SKIP_CATEGORY.match(name):
                continue
            for member in members:
                if member in product_urls:
                    candidates[member].append(name)

    def category_for(product: dict) -> str:
        # Prefer the site's own category names, most specific (shortest) first.
        names = sorted(set(candidates.get(product["url"], [])), key=len)
        votes = [g for g in (group_for(n) for n in names) if g]
        if votes:
            return collections.Counter(votes).most_common(1)[0][0]
        slug = product["url"].rsplit("/", 1)[-1].replace("-", " ")
        return group_for(f"{product['title']} {slug}") or "Other Courses"

    courses, seen = [], set()
    for product in products:
        code = (product["code"] or "").strip()
        key = code or product["url"]
        if key in seen:
            continue
        seen.add(key)
        badges = set(product["badges"])
        category = category_for(product)
        courses.append({
            "id": key,
            "title": product["title"],
            "courseCode": code,
            "category": category,
            "icon": ICONS[category],
            "summary": product["summary"],
            "duration": duration_text(product["hours"]),
            "delivery": product["mode"],
            "fee": round(product["price"], 2),
            "isWSQ": code.upper().startswith("TGS"),
            "sfc": "sfc" in badges,
            "sfec": "sfec" in badges,
            "psea": "psea" in badges,
            "utap": "utap" in badges,
            "ibf": "ibf" in badges,
            "url": product["url"],
        })

    courses.sort(key=lambda c: (c["category"], c["title"]))
    with open(args.out, "w", encoding="utf-8") as handle:
        json.dump(courses, handle, indent=1, ensure_ascii=False)
        handle.write("\n")

    wsq = sum(1 for c in courses if c["isWSQ"])
    print(f"wrote {args.out}: {len(courses)} courses ({wsq} WSQ, {len(courses) - wsq} non-WSQ)",
          file=sys.stderr)
    for name, count in collections.Counter(c["category"] for c in courses).most_common():
        print(f"  {count:4d}  {name}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
