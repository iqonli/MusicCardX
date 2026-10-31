import com.iqonli.musiccardx.StorageMaintenance;
import java.nio.file.*;
import java.io.*;
import java.util.*;

public class StorageMaintenanceTest {
  static File file(File root, String path, long bytes, long age) throws Exception {
    File f = new File(root, path); f.getParentFile().mkdirs();
    try(RandomAccessFile out = new RandomAccessFile(f,"rw")){out.setLength(bytes);}
    f.setLastModified(System.currentTimeMillis()-age); return f;
  }
  static void check(boolean value, String message) {if(!value)throw new AssertionError(message);}
  public static void main(String[] args) throws Exception {
    File root=Files.createTempDirectory("mcx-storage-test").toFile();
    try {
      File files=new File(root,"files"), cache=new File(root,"cache");
      StorageMaintenance s=new StorageMaintenance(files,cache);
      File current=file(files,"covers/current.image",10,120_000),preset=file(files,"covers/preset.image",10,120_000);
      File orphan=file(files,"covers/old.image",10,120_000),recent=file(files,"covers/new.image",10,0);
      File oldTemp=file(cache,"audio-import/old.audio",10,900_000),active=file(cache,"audio-import/active.audio",10,900_000);
      s.leases.add(active.getPath());
      File clip=file(cache,"images/clip.png",10,99_000_000),share=file(cache,"images/share.png",10,0);
      File stale=file(cache,"images/stale.png",10,99_000_000);
      File huge=file(cache,"images/huge.png",40L*1024*1024,1_000);
      File exported=file(root,"user/output.png",10,99_000_000);
      s.clean(Set.of(current.getPath(),preset.getPath()),clip.getName(),false);
      check(current.exists()&&preset.exists(),"current/preset covers retained");
      check(!orphan.exists()&&recent.exists(),"orphan removed; new picker transaction safe");
      check(!oldTemp.exists()&&active.exists(),"temporary audio removed; active import leased");
      check(clip.exists()&&share.exists()&&!stale.exists()&&!huge.exists(),"clipboard and current share protected, old shares bounded");
      check(exported.exists(),"exported user image untouched");
      s.release(active.getPath());check(!active.exists(),"processed/cancelled audio copy released");
      s.release(exported.getPath());check(exported.exists(),"external source never deleted by release");
      s.clean(null,clip.getName(),true);check(recent.exists(),"invalid catalog prevents cover deletion");
      s.clean(Set.of(current.getPath(),preset.getPath()),clip.getName(),true);check(!recent.exists(),"next startup clears abandoned transaction");
      System.out.println("StorageMaintenance: 9 scenarios passed");
    } finally {
      try(var paths=Files.walk(root.toPath())) {paths.sorted(Comparator.reverseOrder()).forEach(p->{try{Files.delete(p);}catch(Exception ignored){}});}
    }
  }
}
