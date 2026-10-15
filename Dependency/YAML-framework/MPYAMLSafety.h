#ifndef MP_YAML_SAFETY_H
#define MP_YAML_SAFETY_H

#include <yaml.h>

enum {
    MPYAMLMaxBytes = 64 * 1024,
    MPYAMLMaxEvents = 4096,
    MPYAMLMaxDepth = 64
};

/* Validate before composition: LibYAML 0.2.5 has no composer depth limit.
 * Aliases are intentionally unsupported, so cyclic object graphs never form.
 * This function is also exercised by the standalone native regression test.
 */
static int MPYAMLInputIsSafe(const unsigned char *bytes, size_t length)
{
    if (length > MPYAMLMaxBytes)
        return 0;

    yaml_parser_t parser;
    if (!yaml_parser_initialize(&parser))
        return 0;
    yaml_parser_set_input_string(&parser, bytes ? bytes
        : (const unsigned char *)"", length);

    size_t count = 0;
    size_t depth = 0;
    int valid = 0;
    int done = 0;
    while (!done)
    {
        yaml_event_t event;
        if (!yaml_parser_parse(&parser, &event))
            break;

        int rejected = ++count > MPYAMLMaxEvents;
        switch (event.type)
        {
            case YAML_ALIAS_EVENT:
                rejected = 1;
                break;
            case YAML_SEQUENCE_START_EVENT:
            case YAML_MAPPING_START_EVENT:
                rejected |= ++depth > MPYAMLMaxDepth;
                break;
            case YAML_SEQUENCE_END_EVENT:
            case YAML_MAPPING_END_EVENT:
                if (!depth)
                    rejected = 1;
                else
                    --depth;
                break;
            case YAML_STREAM_END_EVENT:
                done = 1;
                valid = depth == 0;
                break;
            default:
                break;
        }
        yaml_event_delete(&event);
        if (rejected)
        {
            valid = 0;
            break;
        }
    }
    yaml_parser_delete(&parser);
    return valid;
}

#endif
