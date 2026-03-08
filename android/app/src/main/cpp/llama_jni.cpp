#include <jni.h>
#include <string>
#include <vector>
#include <android/log.h>
#include "llama.h"

#define LOG_TAG "EdgeChat"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,  LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// Inference parameters — tuned for real device (fast + accurate)
static const int   N_CTX          = 1024;
static const int   N_BATCH        = 512;
static const int   N_THREADS      = 4;
static const int   N_PREDICT      = 200;
static const float TEMPERATURE    = 0.15f; // lower = more factual, less creative
static const float TOP_P          = 0.75f; // tighter nucleus = fewer wild token choices
static const int   TOP_K          = 30;   // fewer candidates = more grounded
static const float REPEAT_PENALTY = 1.15f; // stronger penalty = less looping
static const int   PENALTY_LAST_N = 64;

struct EdgeContext {
    llama_model*   model;
    llama_context* ctx;
    llama_sampler* sampler;
};

extern "C" {

JNIEXPORT jlong JNICALL
Java_com_edgechat_LlamaEngine_loadModel(JNIEnv* env, jobject, jstring jModelPath) {
    llama_backend_init();

    const char* path = env->GetStringUTFChars(jModelPath, nullptr);
    LOGI("Loading model: %s", path);

    llama_model_params model_params = llama_model_default_params();
    model_params.n_gpu_layers = 0; // CPU only; Android GPU compute not stable across devices

    llama_model* model = llama_model_load_from_file(path, model_params);
    env->ReleaseStringUTFChars(jModelPath, path);

    if (!model) {
        LOGE("Failed to load model");
        return 0;
    }

    llama_context_params ctx_params = llama_context_default_params();
    ctx_params.n_ctx      = N_CTX;
    ctx_params.n_batch    = N_BATCH;
    ctx_params.n_threads  = N_THREADS;
    ctx_params.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_AUTO;

    llama_context* ctx = llama_init_from_model(model, ctx_params);
    if (!ctx) {
        LOGE("Failed to create context");
        llama_model_free(model);
        return 0;
    }

    // Build sampler chain: top-k → top-p → temperature → repeat penalty → sample
    llama_sampler* sampler = llama_sampler_chain_init(llama_sampler_chain_default_params());
    llama_sampler_chain_add(sampler, llama_sampler_init_top_k(TOP_K));
    llama_sampler_chain_add(sampler, llama_sampler_init_top_p(TOP_P, 1));
    llama_sampler_chain_add(sampler, llama_sampler_init_temp(TEMPERATURE));
    llama_sampler_chain_add(sampler, llama_sampler_init_penalties(PENALTY_LAST_N, REPEAT_PENALTY, 0.0f, 0.0f));
    llama_sampler_chain_add(sampler, llama_sampler_init_dist(LLAMA_DEFAULT_SEED));

    LOGI("Model loaded successfully");
    return reinterpret_cast<jlong>(new EdgeContext{model, ctx, sampler});
}

JNIEXPORT void JNICALL
Java_com_edgechat_LlamaEngine_runCompletion(JNIEnv* env, jobject, jlong handle,
                                             jstring jPrompt, jobject callback) {
    auto* ec = reinterpret_cast<EdgeContext*>(handle);
    if (!ec) return;

    const char* prompt_cstr = env->GetStringUTFChars(jPrompt, nullptr);
    const llama_vocab* vocab = llama_model_get_vocab(ec->model);

    // Tokenize
    int n_tokens = -llama_tokenize(vocab, prompt_cstr, (int32_t)strlen(prompt_cstr),
                                   nullptr, 0, true, true);
    std::vector<llama_token> tokens(n_tokens);
    llama_tokenize(vocab, prompt_cstr, (int32_t)strlen(prompt_cstr),
                   tokens.data(), n_tokens, true, true);
    env->ReleaseStringUTFChars(jPrompt, prompt_cstr);

    // Process prompt
    llama_batch batch = llama_batch_get_one(tokens.data(), (int32_t)tokens.size());
    if (llama_decode(ec->ctx, batch) != 0) {
        LOGE("Prompt decode failed");
        return;
    }

    // Get Kotlin callback method
    jclass  cbClass  = env->GetObjectClass(callback);
    jmethodID onToken = env->GetMethodID(cbClass, "onToken", "(Ljava/lang/String;)V");

    // Generate tokens
    char piece_buf[256];
    for (int i = 0; i < N_PREDICT; i++) {
        llama_token token = llama_sampler_sample(ec->sampler, ec->ctx, -1);

        if (llama_vocab_is_eog(vocab, token)) break;

        int len = llama_token_to_piece(vocab, token, piece_buf, sizeof(piece_buf), 0, true);
        if (len > 0) {
            piece_buf[len] = '\0';
            jstring jpiece = env->NewStringUTF(piece_buf);
            env->CallVoidMethod(callback, onToken, jpiece);
            env->DeleteLocalRef(jpiece);
        }

        llama_sampler_accept(ec->sampler, token);

        llama_token single = token;
        batch = llama_batch_get_one(&single, 1);
        if (llama_decode(ec->ctx, batch) != 0) break;
    }

    // Clear KV cache and reset sampler so the next query starts fresh
    llama_memory_clear(llama_get_memory(ec->ctx), false);
    llama_sampler_reset(ec->sampler);
}

JNIEXPORT void JNICALL
Java_com_edgechat_LlamaEngine_freeModel(JNIEnv*, jobject, jlong handle) {
    auto* ec = reinterpret_cast<EdgeContext*>(handle);
    if (ec) {
        llama_sampler_free(ec->sampler);
        llama_free(ec->ctx);
        llama_model_free(ec->model);
        delete ec;
    }
    llama_backend_free();
}

} // extern "C"
