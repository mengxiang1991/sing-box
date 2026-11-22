package main

import (
	"strings"
	"testing"
)

func TestReplaceRules(t *testing.T) {
	original := "mode: rule\ndns:\n  enable: false\nrules: ['MATCH,DIRECT']\n"
	if rules := readRules(original); rules != `["MATCH,DIRECT"]` {
		t.Fatalf("unexpected original rules %s", rules)
	}
	newRules := `["DOMAIN,example.com,REJECT","MATCH,DIRECT"]`
	updated := replaceRules(original, newRules)
	if updated == "" || readRules(updated) != newRules || !strings.Contains(updated, "enable: false") {
		t.Fatal("the updated document lost rules or unrelated DNS settings")
	}
	if replaceRules(original, `["MATCH,Unknown"]`) != "" {
		t.Fatal("accepted an invalid rule")
	}
}
