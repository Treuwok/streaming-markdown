#include "streaming_markdown.h"

#include <cstdlib>
#include <string>

namespace {

std::string g_json_result;

const char *copy_result_and_free(const char *raw) {
  if (raw == nullptr) {
    g_json_result = "";
    return g_json_result.c_str();
  }
  g_json_result = raw;
  streaming_markdown_rope_free_c_string(raw);
  return g_json_result.c_str();
}

}  // namespace

extern "C" {

const char *streaming_markdown_web_parse_blocks_json(const char *utf8_text) {
  return copy_result_and_free(streaming_markdown_parse_blocks_to_json(utf8_text));
}

const char *streaming_markdown_web_parse_inlines_json(const char *utf8_text) {
  return copy_result_and_free(
      streaming_markdown_parse_inlines_to_json(utf8_text));
}

const char *streaming_markdown_web_block_nodes_json(const char *utf8_text,
                                                    unsigned int max_nodes) {
  void *session = streaming_markdown_incremental_create();
  if (session == nullptr) {
    g_json_result = "[]";
    return g_json_result.c_str();
  }

  const bool ok = streaming_markdown_incremental_set_text(session, utf8_text);
  const char *raw = ok
                        ? streaming_markdown_incremental_block_nodes_json(
                              session, max_nodes == 0 ? 20000 : max_nodes)
                        : nullptr;
  streaming_markdown_incremental_destroy(session);
  return copy_result_and_free(raw);
}

}  // extern "C"
