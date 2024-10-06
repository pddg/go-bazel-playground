package reverse_test

import (
	"testing"

	"github.com/pddg/go-bazel-playground/internal/reverse"
)

func TestString(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name     string
		given    string
		expected string
	}{
		{
			name:     "empty",
			given:    "",
			expected: "",
		},
		{
			name:     "single",
			given:    "a",
			expected: "a",
		},
		{
			name:     "multiple",
			given:    "abc",
			expected: "cba",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			actual := reverse.String(tt.given)
			if actual != tt.expected {
				t.Errorf("expected: %s, actual: %s", tt.expected, actual)
			}
		})
	}
}
