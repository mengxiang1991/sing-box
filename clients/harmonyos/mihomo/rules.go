package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"io"

	"go.yaml.in/yaml/v3"
)

func ruleDocument(text string) (*yaml.Node, *yaml.Node, error) {
	decoder := yaml.NewDecoder(bytes.NewBufferString(text))
	var document yaml.Node
	if err := decoder.Decode(&document); err != nil {
		return nil, nil, err
	}
	var extra yaml.Node
	if decoder.Decode(&extra) != io.EOF || len(document.Content) != 1 || document.Content[0].Kind != yaml.MappingNode {
		return nil, nil, errors.New("expected one YAML mapping")
	}
	return &document, document.Content[0], nil
}

func findRules(mapping *yaml.Node) *yaml.Node {
	for i := 0; i < len(mapping.Content); i += 2 {
		if mapping.Content[i].Value == "rules" {
			return mapping.Content[i+1]
		}
	}
	return nil
}

func readRules(text string) string {
	_, mapping, err := ruleDocument(text)
	if err != nil {
		return ""
	}
	values := []string{}
	if node := findRules(mapping); node != nil && node.Decode(&values) != nil {
		return ""
	}
	if values == nil {
		values = []string{}
	}
	result, _ := json.Marshal(values)
	return string(result)
}

func replaceRules(text, changes string) string {
	document, mapping, err := ruleDocument(text)
	if err != nil {
		return ""
	}
	var values []string
	if json.Unmarshal([]byte(changes), &values) != nil || values == nil {
		return ""
	}
	replacement := &yaml.Node{}
	if replacement.Encode(values) != nil {
		return ""
	}
	if current := findRules(mapping); current != nil {
		replacement.HeadComment = current.HeadComment
		replacement.LineComment = current.LineComment
		replacement.FootComment = current.FootComment
		*current = *replacement
	} else {
		mapping.Content = append(mapping.Content, &yaml.Node{Kind: yaml.ScalarNode, Value: "rules"}, replacement)
	}
	var buffer bytes.Buffer
	encoder := yaml.NewEncoder(&buffer)
	encoder.SetIndent(2)
	if encoder.Encode(document) != nil || encoder.Close() != nil || !checkProfile(buffer.String()) {
		return ""
	}
	return buffer.String()
}
