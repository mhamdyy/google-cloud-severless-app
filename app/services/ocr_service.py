import re
from datetime import datetime, timezone
from collections import Counter
from typing import Tuple, List

STOP_WORDS = {
    "the", "a", "an", "and", "or", "in", "on", "at", "to", "for", "of", "with",
    "by", "is", "it", "this", "that", "from", "as", "be", "are", "was", "were"
}

def simulated_ocr_process(content_bytes: bytes, filename: str) -> Tuple[int, List[str]]:
    """
    Simulates OCR and text analysis.
    For text-like files, analyzes words and derives frequency tags.
    For other files, provides a structured simulated fallback.
    """
    is_text = filename.lower().endswith((".txt", ".md", ".csv", ".json", ".log"))
    
    if is_text:
        try:
            text = content_bytes.decode("utf-8", errors="ignore")
        except Exception:
            text = ""
    else:
        # For non-text/binary formats (e.g. image, pdf), simulate OCR by generating mock extracted tokens
        text = f"Simulated OCR extract for binary document {filename} content classification processed successfully"

    words = re.findall(r"\b[A-Za-z]{3,}\b", text.lower())
    word_count = len(words)

    # Filter stopwords and find top 5 tags
    filtered_words = [w for w in words if w not in STOP_WORDS]
    word_counts = Counter(filtered_words)
    top_tags = [w for w, _ in word_counts.most_common(5)]

    if not top_tags:
        top_tags = ["document", "unclassified"]

    return word_count, top_tags
