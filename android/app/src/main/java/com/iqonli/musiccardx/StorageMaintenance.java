package com.iqonli.musiccardx;

import java.io.File;
import java.io.IOException;
import java.util.*;

/** Runs on the host's single I/O executor. Exported user files are never visited. */
public final class StorageMaintenance {
    private final File filesDir, cacheDir;
    public final Set<String> leases = new HashSet<>();
    public StorageMaintenance(File filesDir, File cacheDir) {
        this.filesDir = filesDir; this.cacheDir = cacheDir;
    }
    public void release(String path) throws IOException {
        leases.remove(path);
        File file = new File(path).getCanonicalFile();
        for (String name : new String[]{"audio-import", "incoming-images"}) {
            if (file.getParentFile().equals(new File(cacheDir, name).getCanonicalFile())) file.delete();
        }
    }
    private static List<File> children(File directory) {
        File[] list = directory.listFiles();
        return list == null ? new ArrayList<>() : new ArrayList<>(Arrays.asList(list));
    }
    public void clean(Set<String> referencedCovers, String clipboardFile, boolean startup) throws IOException {
        Set<String> keep = new HashSet<>();
        for (String path : leases) keep.add(new File(path).getCanonicalPath());
        long now = System.currentTimeMillis();
        for (String name : new String[]{"audio-import", "incoming-images", "font-import"}) {
            for (File file : children(new File(cacheDir, name))) {
                if (file.isFile() && !keep.contains(file.getCanonicalPath()) &&
                    (startup || now - file.lastModified() > 10 * 60_000L)) file.delete();
            }
        }
        // null means a state/preset could not be read: retain all covers conservatively.
        if (referencedCovers != null) {
            Set<String> referenced = new HashSet<>(keep);
            for (String path : referencedCovers) referenced.add(new File(path).getCanonicalPath());
            for (File file : children(new File(filesDir, "covers"))) {
                if (file.isFile() && !referenced.contains(file.getCanonicalPath()) &&
                    (startup || now - file.lastModified() > 60_000L)) file.delete();
            }
        }
        List<File> images = children(new File(cacheDir, "images"));
        images.removeIf(file -> !file.isFile());
        images.sort((a,b) -> Long.compare(b.lastModified(), a.lastModified()));
        long budget = 32 * 1024 * 1024L;
        for (int i = 0; i < images.size(); i++) {
            File image = images.get(i);
            boolean protectedFile = image.getName().equals(clipboardFile) || i == 0;
            if (!protectedFile && (now - image.lastModified() > 6 * 60 * 60_000L || image.length() > budget)) image.delete();
            else budget = Math.max(0L, budget - image.length());
        }
    }
}
