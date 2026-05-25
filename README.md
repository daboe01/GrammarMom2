# AI-Powered Writing Assistant

A web-based, desktop-class text editor and proofreading suite. The application analyzes narrative text paragraph-by-paragraph, highlights errors (spelling, grammar, clarity, and style) with visual overlays, and allows users to apply suggested corrections with a single click.

This project is built using a decoupled client-server architecture:
*   **Frontend**: A desktop-style rich-text UI built on **Cappuccino (Objective-J)**.
*   **Backend**: A lightweight asynchronous API gateway built on **Mojolicious::Lite (Perl)**.

---
<img width="1011" height="837" alt="Bildschirmfoto 2026-05-23 um 19 35 44" src="https://github.com/user-attachments/assets/57864753-bbd3-4ac8-8c76-0979b2eb6f8b" />

## Key Features

*   **Multilingual Analysis**: Real-time language switching (German / English) utilizing different LLM run configurations (`48` and `49`).
*   **Context-Aware Higlighting**: Highlights text segments based on four distinct categories:
    *   🔴 **Spelling**: Typos and spelling mistakes.
    *   🔵 **Grammar**: Syntax issues, tense issues, and punctuation.
    *   🟢 **Clarity**: Passive voice, overly wordy sentences, or confusing phrasing.
    *   🟣 **Style**: Tone improvements and formal adjustments.
*   **Fault-Tolerant String Matching**: Instead of relying on LLM character count offsets (which are often inaccurate), the Perl backend programmatically computes exact offsets using robust substring searches (`index`).
*   **Dynamic Range Shifting**: Applying a correction dynamically shifts the offsets of all remaining alerts in the paragraph, preventing highlight misalignment during active editing.

---

## Architecture Overview

```text
 ┌────────────────────────┐         POST /DBB/analyze_text         ┌─────────────────────────┐
 │                        │  ───────────────────────────────────>  │                         │
 │  Cappuccino Frontend   │                                        │   Mojolicious Backend   │
 │     (Objective-J)      │  <───────────────────────────────────  │         (Perl)          │
 │                        │        JSON Array of Paragraphs        │                         │
 └────────────────────────┘                                        └────────────┬────────────┘
                                                                                │
                                                                                │  POST (Asynchronous)
                                                                                ▼
                                                                   ┌─────────────────────────┐
                                                                   │       LLM Service       │
                                                                   │  (Run 48: EN / 49: DE)  │
                                                                   └─────────────────────────┘
```

---

## Tech Stack

*   **Frontend**: Objective-J, Cappuccino SDK (AppKit & Foundation ports for the web)
*   **Backend**: Perl 5, Mojolicious::Lite, Mojo::UserAgent, Mojo::Promise
*   **Integration**: JSON REST API

---

## Getting Started

### Prerequisites

*   **Frontend**: A local web server to serve the static Cappuccino assets (e.g., Python's `http.server` or Apache/Nginx).
*   **Backend**: Perl 5 (ActivePerl or Perlbrew) with Mojolicious installed.

### Installation

1.  **Clone the repository**:
    ```bash
    git clone https://github.com/your-username/ai-writing-assistant.git
    cd ai-writing-assistant
    ```

2.  **Install Perl dependencies**:
    ```bash
    cpanm Mojolicious
    ```

3.  **Set Environment Variables**:
    Configure the backend to point to your LLM / Vectorstore endpoint:
    ```bash
    export VECTORSTORE_URL="http://your-llm-gateway"
    ```

4.  **Start the Backend**:
    Run the server in development mode (using Morbo for auto-reload):
    ```bash
    morbo app.pl
    ```

5.  **Run the Frontend**:
    Open `http://localhost:3000/Frontend/index.html` in your browser.

---

## API Specification

### Text Analysis Endpoint

*   **Route**: `POST /DBB/analyze_text`
*   **Headers**: `Content-Type: application/json`
*   **Request Payload**:
    ```json
    {
      "text": "This is some narrative text. It has a mispelled word.",
      "run_id": 48
    }
    ```
*   **Response Payload**:
    ```json
    {
      "paragraphs": [
        {
          "paragraph_index": 0,
          "text": "This is some narrative text. It has a mispelled word.",
          "alerts": [
            {
              "id": "alert_0_0",
              "category": "spelling",
              "title": "Spelling Correction",
              "original_text": "mispelled",
              "suggested_text": "misspelled",
              "offset": 38,
              "length": 9,
              "explanation": "The word is spelled with double 's'."
            }
          ]
        }
      ]
    }
    ```

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
