import sys
import json
import os

os.environ["TF_CPP_MIN_LOG_LEVEL"] = "3"

try:
    from sentence_transformers import SentenceTransformer
except ImportError:
    print("Missing dependency: sentence-transformers", file=sys.stderr)
    sys.exit(1)


MODEL_NAME = "all-MiniLM-L6-v2"


def main() -> int:
    if len(sys.argv) != 3:
        print("Usage: python embeddings_local.py <input_file> <output_file>", file=sys.stderr)
        return 1

    input_file = sys.argv[1]
    output_file = sys.argv[2]

    model = SentenceTransformer(MODEL_NAME)

    with open(input_file, "r", encoding="utf-8") as file:
        text = file.read()

    embedding = model.encode([text])[0].tolist()

    with open(output_file, "w", encoding="utf-8") as file:
        json.dump(embedding, file)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
