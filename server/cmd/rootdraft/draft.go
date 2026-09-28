package main

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"

	"github.com/tmc/langchaingo/llms"
	"github.com/tmc/langchaingo/llms/openai"
)

// The model, reached through langchaingo's OpenAI-shaped client.
//
// OpenAI-shaped rather than any one vendor's SDK, because the wire format is
// what every provider implements: the same command reaches a frontier model, a
// cheap one, an Arabic-specialised one, or something served from this machine,
// by changing -base-url and -model rather than a dependency. Drafting 1,642
// roots is exactly the job where that choice belongs to whoever runs it.
//
// The default points at Hugging Face's router, which speaks the same shape and
// whose token is already on this machine under `hf auth`.

// What one root's entry comes back as. Four fields, two registers, two
// languages — and nothing else, so a run that starts talking is a run that
// failed rather than a row that is quietly prose.
type drafted struct {
	SenseEn  string `json:"sense_en"`
	SenseFr  string `json:"sense_fr"`
	PoeticEn string `json:"poetic_en"`
	PoeticFr string `json:"poetic_fr"`
}

func (d drafted) complete() error {
	for _, f := range []struct{ name, val string }{
		{"sense_en", d.SenseEn}, {"sense_fr", d.SenseFr},
		{"poetic_en", d.PoeticEn}, {"poetic_fr", d.PoeticFr},
	} {
		if strings.TrimSpace(f.val) == "" {
			return fmt.Errorf("%s is empty", f.name)
		}
	}
	return nil
}

// A sense is a claim about the word and never about a verse. server/cmd/etl's
// Check enforces that over the whole file at build time; catching it here means a
// bad row is never written, so a re-run has nothing to clean up after.
func (d drafted) aboutTheWordOnly() error {
	for _, text := range []string{d.SenseEn, d.SenseFr, d.PoeticEn, d.PoeticFr} {
		if m := verseRef.FindString(text); m != "" {
			return fmt.Errorf("cites verse %s, which is tafsir rather than lexicography", m)
		}
	}
	return nil
}

type drafter struct {
	llm      *openai.LLM
	jsonMode bool
}

func newDrafter(baseURL, apiKey, model string, jsonMode bool) (drafter, error) {
	llm, err := openai.New(
		openai.WithBaseURL(baseURL),
		openai.WithToken(apiKey),
		openai.WithModel(model),
	)
	if err != nil {
		return drafter{}, err
	}
	return drafter{llm: llm, jsonMode: jsonMode}, nil
}

// draft asks once and parses. A reply that is not the one object asked for is an
// error rather than something to salvage: the prompt says "no prose before or
// after", so digging JSON out of chatter would hide a prompt worth fixing.
func (d drafter) draft(ctx context.Context, prompt string) (drafted, string, error) {
	opts := []llms.CallOption{llms.WithMaxTokens(4000)}
	// Not every provider honours it and some reject it outright, so it is a flag
	// rather than an assumption.
	if d.jsonMode {
		opts = append(opts, llms.WithJSONMode())
	}
	res, err := d.llm.GenerateContent(ctx, []llms.MessageContent{
		llms.TextParts(llms.ChatMessageTypeHuman, prompt),
	}, opts...)
	if err != nil {
		return drafted{}, "", err
	}
	if len(res.Choices) == 0 {
		return drafted{}, "", fmt.Errorf("the model answered with no choices")
	}
	choice := res.Choices[0]
	// A cut-off answer is a bad row, not a short one: say so rather than writing
	// half a sense.
	if choice.StopReason != "" && choice.StopReason != "stop" {
		return drafted{}, choice.Content,
			fmt.Errorf("the answer stopped on %q rather than finishing", choice.StopReason)
	}
	text := unfence(choice.Content)
	var out drafted
	if err := json.Unmarshal([]byte(text), &out); err != nil {
		return drafted{}, text, fmt.Errorf("not the one JSON object the prompt asks for: %w", err)
	}
	if err := out.complete(); err != nil {
		return out, text, err
	}
	if err := out.aboutTheWordOnly(); err != nil {
		return out, text, err
	}
	return out, text, nil
}

// A fenced block is the one deviation worth tolerating: several models add it
// however the prompt is worded, and it changes nothing about the JSON inside.
func unfence(s string) string {
	s = strings.TrimSpace(s)
	s = strings.TrimPrefix(s, "```json")
	s = strings.TrimPrefix(s, "```")
	s = strings.TrimSuffix(strings.TrimSpace(s), "```")
	return strings.TrimSpace(s)
}
