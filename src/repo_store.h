/* repo_store.h -- persistence for the user's saved repo URL list.
   /mnt/us/tachikindle/repos.json = {"repos":["https://...","..."]}.
   Kept separate from repo.c (which only talks to remote repos) since
   this is purely local config I/O. */
#ifndef TK_REPO_STORE_H
#define TK_REPO_STORE_H

#include <stddef.h>

#define REPO_STORE_MAX 16
#define REPO_STORE_URL_LEN 512

typedef struct {
    char urls[REPO_STORE_MAX][REPO_STORE_URL_LEN];
    int count;
} repo_store_t;

/* Loads from path; missing file is not an error (count=0). Returns 0
   on success (including "file absent"), -1 on a real I/O/parse error
   on a file that does exist. */
int repo_store_load(repo_store_t *store, const char *path);

/* Overwrites path with the current contents. Returns 0 on success. */
int repo_store_save(const repo_store_t *store, const char *path);

/* Appends url if there's room and it isn't already present. Returns
   0 on success, -1 if full or duplicate. */
int repo_store_add(repo_store_t *store, const char *url);

/* Removes the entry at index i, shifting later entries down. */
int repo_store_remove(repo_store_t *store, int i);

#endif
