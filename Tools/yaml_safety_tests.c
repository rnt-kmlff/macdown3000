#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../Dependency/YAML-framework/MPYAMLSafety.h"

static int safe(const char *text)
{
    return MPYAMLInputIsSafe((const unsigned char *)text, strlen(text));
}

int main(void)
{
    assert(strcmp(yaml_get_version_string(), "0.2.5") == 0);
    assert(safe("title: Example\nitems: [one, two]\n"));
    assert(safe(""));
    assert(!safe("a: &a [*a]\n"));
    assert(!safe("a: &a value\nb: *a\n"));
    assert(!safe("a: [broken\n"));

    char nested[4096];
    memset(nested, '[', 1000);
    nested[1000] = 'x';
    memset(nested + 1001, ']', 1000);
    nested[2001] = 0;
    assert(!safe(nested));
    memset(nested, '[', 64);
    nested[64] = 'x';
    memset(nested + 65, ']', 64);
    nested[129] = 0;
    assert(safe(nested));

    char *large = malloc(MPYAMLMaxBytes + 2);
    memset(large, 'x', MPYAMLMaxBytes + 1);
    large[MPYAMLMaxBytes + 1] = 0;
    assert(!safe(large));
    free(large);

    char wide[20000] = "";
    for (int i = 0; i < 4200; i++)
        strcat(wide, "- x\n");
    assert(!safe(wide));

    char escaped[20000] = "a: !<tag:example.com,";
    for (int i = 0; i < 1024; i++)
        strcat(escaped, "%F0%9F%98%80");
    strcat(escaped, "> value\n");
    assert(safe(escaped));
    char tag[16000] = "a: !<tag:example.com,";
    size_t start = strlen(tag);
    memset(tag + start, 'x', 10000);
    strcpy(tag + start + 10000, "> value\n");
    assert(safe(tag));
    for (int i = 0; i < 1000; i++)
    {
        assert(!safe("a: [broken\n"));
        assert(!safe(nested + 1));
        assert(safe("title: Recovered\n"));
    }
    puts("PASS: patched version, normal/empty data, aliases, nesting boundary, "
         "byte/event budgets, long tags/URI escapes, repeated recovery");
    return 0;
}
