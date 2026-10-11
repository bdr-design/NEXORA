"""Read-only public OpenRouter catalog and coding-index introspection; no NEXORA source sent."""
import json
import os
import re
from urllib.error import HTTPError, URLError
from urllib.request import Request, build_opener
from bridge import API, NoRedirect, api_call, free_model, QUALIFIED_FREE_MODELS

def report():
    catalog = api_call("/models").get("data", [])
    if not isinstance(catalog, list):
        print(json.dumps({"quality_probe": "CATALOG_UNAVAILABLE"}))
        return
    free = [m for m in catalog if free_model(m)]
    found = {m["id"]: m for m in free}
    benchmarks = []
    status = "UNAVAILABLE"
    key = os.environ.get("OPENROUTER_API_KEY", "").strip()
    if key:
        url = API + "/benchmarks?source=artificial-analysis&task_type=coding&max_results=200"
        req = Request(url, headers={"Authorization": "Bearer " + key, "Accept": "application/json"})
        try:
            with build_opener(NoRedirect()).open(req, timeout=25) as resp:
                raw = resp.read(1_000_001)
            payload = json.loads(raw)
            values = payload.get("data", [])
            if isinstance(values, list):
                for v in values:
                    if not isinstance(v, dict):
                        continue
                    slug = v.get("model_permaslug", "")
                    if not isinstance(slug, str):
                        continue
                    if not re.fullmatch(r"[A-Za-z0-9_./:-]{1,128}", slug):
                        continue
                    score = v.get("coding_index")
                    if isinstance(score, (int,float)) and not isinstance(score,bool) and 0 <= score <= 100:
                        benchmarks.append({"slug": slug, "coding_index": score,
                                           "intelligence_index": v.get("intelligence_index")})
                status = "OK"
        except (HTTPError, URLError, OSError, ValueError, TypeError):
            status = "UNAVAILABLE"
    selected = []
    for ident in sorted(QUALIFIED_FREE_MODELS):
        entry = found.get(ident)
        selected.append({"model": ident, "free_catalog_present": entry is not None,
                         "context_length": entry.get("context_length") if entry else None,
                         "canonical_slug": entry.get("canonical_slug") if entry else None})
    # This inventory is public identifiers only, never credentials / request bodies.
    free_ids = sorted(m["id"] for m in free
                      if isinstance(m.get("id"),str)
                      and re.fullmatch(r"[A-Za-z0-9_./:-]{1,128}",m["id"]))
    print(json.dumps({"quality_probe": status, "free_count": len(free_ids),
                      "free_ids": free_ids[:100], "qualified": selected,
                      "top_coding_benchmark_public": sorted(
                          benchmarks, key=lambda r:r["coding_index"], reverse=True)[:12]},
                     ensure_ascii=True))

if __name__ == "__main__":
    report()
