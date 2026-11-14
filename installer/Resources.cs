// Resource index reader/writer for the Steam next-gen Metro Redux layout.
// Does not locate games or install files. Callers control all output paths.
using System;
using System.IO;
using System.Text;
using System.Collections.Generic;

namespace LastLightHu {
    public sealed class ResourceEntry {
        public int Record; public ushort Archive; public uint Offset, Packed, Unpacked;
        internal string Name; internal int First, Count; internal bool Directory;
    }
    public sealed class ResourceIndex {
        public static void AtomicWrite(string path,byte[] bytes) {
            string temporary=path+".new-"+Guid.NewGuid().ToString("N");
            try {File.WriteAllBytes(temporary,bytes);if(File.Exists(path))File.Replace(temporary,path,null);else File.Move(temporary,path);}
            finally {if(File.Exists(temporary))File.Delete(temporary);}
        }
        public readonly byte[] Data;
        public readonly List<string> Archives = new List<string>();
        public readonly Dictionary<string,ResourceEntry> Files = new Dictionary<string,ResourceEntry>(StringComparer.OrdinalIgnoreCase);
        readonly List<ResourceEntry> entries = new List<ResourceEntry>();
        readonly uint fileCount, directoryCount;
        readonly int archiveEnd, entriesEnd;
        static readonly UTF8Encoding Utf8 = new UTF8Encoding(false,true);
        public ResourceIndex(byte[] data) {
            Data=data;
            using(var stream=new MemoryStream(data,false)) using(var r=new BinaryReader(stream)) {
                if(data.Length<44) throw new InvalidDataException("INDEX_TRUNCATED");
                stream.Position=24;
                uint archives=r.ReadUInt32(); fileCount=r.ReadUInt32(); directoryCount=r.ReadUInt32();
                if(archives==0 || archives>=65535 || fileCount>1000000 || directoryCount>1000000) throw new InvalidDataException("INDEX_LAYOUT");
                for(int a=0;a<archives;a++) {
                    string name=ReadString(r);
                    if(Path.GetFileName(name)!=name || name.Contains("/") || name.Contains("\\") || !name.EndsWith(".vfs"+name[name.Length-1],StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("ARCHIVE_NAME");
                    Archives.Add(name);uint count=r.ReadUInt32();
                    if(count>10000)throw new InvalidDataException("ARCHIVE_LAYOUT");
                    for(uint i=0;i<count;i++)ReadString(r);
                    r.ReadUInt32();
                }
                archiveEnd=checked((int)stream.Position);
                for(uint i=0;i<fileCount;i++) {
                    var e=new ResourceEntry(); e.Record=checked((int)stream.Position);
                    ushort type=r.ReadUInt16();
                    if(type==0) {e.Archive=r.ReadUInt16();e.Offset=r.ReadUInt32();e.Unpacked=r.ReadUInt32();e.Packed=r.ReadUInt32();if(e.Archive>=archives)throw new InvalidDataException("ARCHIVE_ID");}
                    else if(type==8){e.Directory=true;e.Count=r.ReadUInt16();e.First=checked((int)r.ReadUInt32());}
                    else throw new InvalidDataException("ENTRY_TYPE");
                    int length=r.ReadByte();byte xor=r.ReadByte();
                    if(length<1)throw new InvalidDataException("ENTRY_NAME");
                    byte[] name=r.ReadBytes(length);if(name.Length!=length)throw new EndOfStreamException();
                    for(int n=0;n<length-1;n++)name[n]^=xor;
                    e.Name=Utf8.GetString(name,0,length-1);entries.Add(e);
                }
                entriesEnd=checked((int)stream.Position);
                if((long)entriesEnd+directoryCount*20L+8!=data.Length)throw new InvalidDataException("INDEX_TRAILER");
            }
            if(entries.Count==0 || !entries[0].Directory)throw new InvalidDataException("INDEX_ROOT");
            Walk(0,"",new HashSet<int>());
        }
        static string ReadString(BinaryReader r) {
            var bytes=new List<byte>();
            for(int n=0;n<32768;n++){byte b=r.ReadByte();if(b==0)return Utf8.GetString(bytes.ToArray());bytes.Add(b);}
            throw new InvalidDataException("STRING_LENGTH");
        }
        void Walk(int i,string prefix,HashSet<int> ancestors) {
            if(i<0 || i>=entries.Count || !ancestors.Add(i))throw new InvalidDataException("INDEX_TREE");
            ResourceEntry e=entries[i];string p=(prefix+"/"+e.Name).TrimStart('/').Replace('\\','/');
            if(p.Contains("../") || p.StartsWith("/"))throw new InvalidDataException("RESOURCE_PATH");
            if(e.Directory) {
                if(e.First<0 || (long)e.First+e.Count>entries.Count)throw new InvalidDataException("INDEX_TREE");
                for(int child=e.First;child<e.First+e.Count;child++)Walk(child,p,ancestors);
            } else {
                if(Files.ContainsKey(p))throw new InvalidDataException("DUPLICATE_RESOURCE");Files.Add(p,e);
            }
            ancestors.Remove(i);
        }
        public byte[] Extract(string folder,string resource) {
            ResourceEntry e;if(!Files.TryGetValue(resource,out e))throw new InvalidDataException("RESOURCE_MISSING");
            string path=Path.Combine(folder,Archives[e.Archive]);
            using(var s=File.OpenRead(path)) {
                if((long)e.Offset+e.Packed>s.Length || e.Unpacked>134217728 || e.Packed>150994944)throw new InvalidDataException("RESOURCE_RANGE");
                s.Position=e.Offset;byte[] raw=new byte[e.Packed];int read=0;
                while(read<raw.Length){int n=s.Read(raw,read,raw.Length-read);if(n==0)throw new EndOfStreamException();read+=n;}
                if(e.Packed==e.Unpacked)return raw;
                return DecodeBlocks(raw,checked((int)e.Unpacked));
            }
        }
        static uint U32(byte[] b,int p){if(p<0 || p+4>b.Length)throw new InvalidDataException("LZ4_HEADER");return BitConverter.ToUInt32(b,p);}
        static byte[] DecodeBlocks(byte[] raw,int expected) {
            byte[] output=new byte[expected];int input=0,write=0;
            while(input<raw.Length) {
                uint packed=U32(raw,input),unpacked=U32(raw,input+4);
                if(packed<8 || packed>raw.Length-input)throw new InvalidDataException("LZ4_BLOCK");
                int end=checked(input+(int)packed);input+=8;
                if(packed==unpacked) {
                    int n=end-input;if(n>output.Length-write)throw new InvalidDataException("LZ4_RANGE");Buffer.BlockCopy(raw,input,output,write,n);write+=n;input=end;continue;
                }
                int start=write;
                while(input<end) {
                    int token=raw[input++],literal=token>>4,match=token&15;
                    if(literal==15){int n;do{if(input>=end)throw new InvalidDataException("LZ4_LITERAL");n=raw[input++];literal=checked(literal+n);}while(n==255);}
                    if(literal>end-input || literal>output.Length-write)throw new InvalidDataException("LZ4_RANGE");
                    Buffer.BlockCopy(raw,input,output,write,literal);input+=literal;write+=literal;
                    if(input==end)break;
                    if(input+2>end)throw new InvalidDataException("LZ4_OFFSET");int distance=raw[input]|raw[input+1]<<8;input+=2;
                    if(distance==0 || distance>write || distance>65535)throw new InvalidDataException("LZ4_DISTANCE");
                    if(match==15){int n;do{if(input>=end)throw new InvalidDataException("LZ4_MATCH");n=raw[input++];match=checked(match+n);}while(n==255);}
                    match+=4;if(match>output.Length-write)throw new InvalidDataException("LZ4_RANGE");
                    for(int n=0;n<match;n++){output[write]=output[write-distance];write++;}
                }
                if(write-start!=unpacked)throw new InvalidDataException("LZ4_BLOCK_SIZE");
            }
            if(write!=expected)throw new InvalidDataException("LZ4_FINAL_SIZE");return output;
        }
        public const string DlcLevel = "content/maps/2034/dlc_faction_ganza/level.bin";
        public const string DlcFont = "content/textures/font/font_ganza_loot_hu";
        public const string RegularFont = "content/textures/font/font_font_regular_us";

        public byte[][] Overlay(string archiveName,string[] paths,byte[][] contents) {
            bool exists=Archives.Exists(delegate(string a){return String.Equals(a,archiveName,StringComparison.OrdinalIgnoreCase);});
            if(paths.Length!=contents.Length || paths.Length==0 || exists || Path.GetFileName(archiveName)!=archiveName || archiveName.Contains("\\") || archiveName.Contains("/") || !archiveName.EndsWith(".vfs0",StringComparison.OrdinalIgnoreCase))throw new InvalidDataException("OVERLAY_LAYOUT");
            byte[] modified=(byte[])Data.Clone();var seen=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            byte[] archive;
            var additions=new Dictionary<string,byte[]>(StringComparer.OrdinalIgnoreCase);
            using(var ms=new MemoryStream()) using(var w=new BinaryWriter(ms)) {
                w.Write(0u);w.Write(0u);
                for(int i=0;i<paths.Length;i++) {
                    ResourceEntry e;
                    if(!seen.Add(paths[i]))throw new InvalidDataException("OVERLAY_RESOURCE");
                    uint offset=checked((uint)ms.Position),size=checked((uint)contents[i].Length);
                    if(Files.TryGetValue(paths[i],out e)) {
                        if(paths[i]==DlcFont+".512" || paths[i]==DlcFont+".bin")throw new InvalidDataException("FILE_CONFLICT");
                        using(var es=new MemoryStream(modified,true))using(var ew=new BinaryWriter(es)) {
                            es.Position=e.Record+2;ew.Write(checked((ushort)Archives.Count));ew.Write(offset);ew.Write(size);ew.Write(size);
                        }
                    } else {
                        if(paths[i]!=DlcFont+".512" && paths[i]!=DlcFont+".bin")throw new InvalidDataException("OVERLAY_RESOURCE");
                        using(var record=new MemoryStream())using(var rw=new BinaryWriter(record)) {
                            byte[] name=Utf8.GetBytes(Path.GetFileName(paths[i])+"\0");
                            rw.Write((ushort)0);rw.Write(checked((ushort)Archives.Count));rw.Write(offset);rw.Write(size);rw.Write(size);
                            rw.Write((byte)name.Length);rw.Write((byte)0);rw.Write(name);
                            additions.Add(paths[i],record.ToArray());
                        }
                    }
                    w.Write(contents[i]);
                }
                uint payload=checked((uint)ms.Length-8);w.Write(3u);w.Write(16u);w.Write(Data,8,16);
                ms.Position=4;w.Write(payload);archive=ms.ToArray();
            }
            int insertAt=entries.Count;
            if(additions.Count!=0) {
                ResourceEntry original=Files[RegularFont+".512"];
                int originalId=entries.IndexOf(original);
                ResourceEntry parent=entries.Find(e=>e.Directory && e.Name=="font" && originalId>=e.First && originalId<e.First+e.Count);
                if(parent==null)throw new InvalidDataException("UNSUPPORTED_LAYOUT");
                insertAt=parent.First+parent.Count;
                using(var es=new MemoryStream(modified,true))using(var ew=new BinaryWriter(es)) {
                    foreach(ResourceEntry entry in entries) {
                        if(!entry.Directory)continue;
                        if(entry==parent) { es.Position=entry.Record+2;ew.Write(checked((ushort)(entry.Count+additions.Count))); }
                        else if(entry.First>=insertAt) { es.Position=entry.Record+4;ew.Write(checked((uint)(entry.First+additions.Count))); }
                    }
                    for(int p=entriesEnd;p<modified.Length-8;p+=20) {
                        uint id=BitConverter.ToUInt32(modified,p+16);
                        if(id>=entries.Count || entries[(int)id].Directory)throw new InvalidDataException("UNSUPPORTED_LAYOUT");
                        if(id>=insertAt) { es.Position=p+16;ew.Write(checked(id+(uint)additions.Count)); }
                    }
                }
            }
            byte[] index;
            using(var ms=new MemoryStream())using(var w=new BinaryWriter(ms)) {
                w.Write(Data,0,24);w.Write(checked((uint)Archives.Count+1));w.Write(checked(fileCount+(uint)additions.Count));w.Write(directoryCount);
                w.Write(Data,36,archiveEnd-36);w.Write(Utf8.GetBytes(archiveName));w.Write((byte)0);w.Write(0u);w.Write(checked((uint)archive.Length));
                int split=insertAt==entries.Count?entriesEnd:entries[insertAt].Record;
                w.Write(modified,archiveEnd,split-archiveEnd);
                foreach(byte[] record in additions.Values)w.Write(record);
                w.Write(modified,split,modified.Length-split);index=ms.ToArray();
            }
            var check=new ResourceIndex(index);if(check.Files.Count!=Files.Count+additions.Count || check.Archives.Count!=Archives.Count+1)throw new InvalidDataException("OVERLAY_VERIFY");
            return new byte[][]{index,archive};
        }
        // Experimental native UI horizontal alignment, not coordinate padding.
        static List<int> UiChunks(byte[] data,int start,int end) {
            var result=new List<int>();int p=start;
            while(p<end) {
                if(end-p<8)throw new InvalidDataException("UI_LAYOUT");
                uint size=BitConverter.ToUInt32(data,p+4);
                if(size>(uint)(end-p-8))throw new InvalidDataException("UI_LAYOUT");
                result.Add(p);p=checked(p+8+(int)size);
            }
            return result;
        }
        static int UiEnd(byte[] data,int p){return checked(p+8+(int)BitConverter.ToUInt32(data,p+4));}
        public static byte[] ArrangeBackButtons(byte[] target) {
            byte[] output=(byte[])target.Clone();int roots=0,matched=0,chapterMatched=0;
            byte[] marker=Utf8.GetBytes("$back\0");
            foreach(int root in UiChunks(target,0,target.Length)) {
                int rootEnd=UiEnd(target,root);bool match=false;
                for(int i=root+8;i<=rootEnd-marker.Length;i++) {
                    int j=0;while(j<marker.Length && target[i+j]==marker[j])j++;
                    if(j==marker.Length){match=true;break;}
                }
                if(!match)continue;roots++;
                if(target[root+8]!=4)throw new InvalidDataException("UI_LAYOUT");
                var fields=UiChunks(target,root+9,rootEnd);
                if(fields.Count!=2 || BitConverter.ToUInt32(target,fields[0])!=1 || BitConverter.ToUInt32(target,fields[1])!=2)throw new InvalidDataException("UI_LAYOUT");
                int sp=fields[1]+8,send=UiEnd(target,fields[1]);uint count=BitConverter.ToUInt32(target,sp);sp+=4;
                var strings=new List<string>();
                for(uint n=0;n<count;n++) {
                    int begin=sp;while(sp<send && target[sp]!=0)sp++;
                    if(sp==send)throw new InvalidDataException("UI_LAYOUT");
                    strings.Add(Utf8.GetString(target,begin,sp-begin));sp++;
                }
                if(sp!=send)throw new InvalidDataException("UI_LAYOUT");
                var containers=UiChunks(target,fields[0]+8,UiEnd(target,fields[0]));
                if(containers.Count!=1)throw new InvalidDataException("UI_LAYOUT");
                int ca=containers[0]+8,ce=UiEnd(target,containers[0]);
                if(target[ca]!=4)throw new InvalidDataException("UI_LAYOUT");
                var screens=UiChunks(target,ca+5,ce);
                if(screens.Count!=BitConverter.ToUInt32(target,ca+1))throw new InvalidDataException("UI_LAYOUT");
                foreach(int screen in screens) {
                    int start=screen+8,end=UiEnd(target,screen);
                    uint screenName=BitConverter.ToUInt32(target,start+1);
                    if(screenName>=strings.Count)throw new InvalidDataException("UI_LAYOUT");
                    bool chapter=strings[(int)screenName]=="chapters_menu";
                    if(end-start<35 || target[start]!=4)throw new InvalidDataException("UI_LAYOUT");
                    foreach(int group in UiChunks(target,start+35,end)) {
                        int a=group+8,ae=UiEnd(target,group);
                        if(ae-a<5 || target[a]!=4)continue;
                        var items=UiChunks(target,a+5,ae);
                        if(items.Count!=BitConverter.ToUInt32(target,a+1))throw new InvalidDataException("UI_LAYOUT");
                        int chapterLeft=-1,chapterRight=-1;
                        if(chapter) {
                            foreach(int item in items) {
                                int b=item+8,len=UiEnd(target,item)-b;
                                if(len<31 || target[b]!=4)throw new InvalidDataException("UI_LAYOUT");
                                uint ni=BitConverter.ToUInt32(target,b+5);
                                if(ni>=strings.Count)throw new InvalidDataException("UI_LAYOUT");
                                if(strings[(int)ni]=="list_box")chapterLeft=BitConverter.ToInt32(target,b+15);
                                if(strings[(int)ni]=="hint_desc")chapterRight=checked(BitConverter.ToInt32(target,b+15)+BitConverter.ToInt32(target,b+23));
                            }
                            if(chapterLeft<0 || chapterRight<=chapterLeft)throw new InvalidDataException("UI_LAYOUT");
                        }
                        foreach(int item in items) {
                            int b=item+8,len=UiEnd(target,item)-b;
                            if(len<9 || target[b]!=4 || BitConverter.ToUInt32(target,b+1)!=3)continue;
                            uint name=BitConverter.ToUInt32(target,b+5);
                            if(name>=strings.Count)throw new InvalidDataException("UI_LAYOUT");
                            string itemName=strings[(int)name];
                            if(chapter && (itemName=="btn_back" || itemName=="btn_play" || itemName=="btn_play_dlc" || itemName=="btn_main_story" || itemName=="btn_new_missions")) {
                                if(len!=112 || BitConverter.ToInt32(target,b+23)<=0 || target[b+32]>2)throw new InvalidDataException("UI_LAYOUT");
                                bool back=itemName=="btn_back";
                                int x=back?checked(chapterRight-BitConverter.ToInt32(target,b+23)):chapterLeft;
                                Buffer.BlockCopy(BitConverter.GetBytes(x),0,output,b+15,4);
                                output[b+32]=(byte)(back?1:0);chapterMatched++;continue;
                            }
                            if(itemName!="btn_back")continue;
                            // Center the complete button in a fixed-width rectangle.
                            // The chapter-page buttons above retain their own layout.
                            if(len!=112)throw new InvalidDataException("UI_LAYOUT");
                            int backWidth=BitConverter.ToInt32(target,b+23);
                            if((backWidth!=0 && backWidth!=200 && backWidth!=400) || BitConverter.ToInt32(target,b+27)!=0 || target[b+46]!=4)continue;
                            uint font=BitConverter.ToUInt32(target,b+56),text=BitConverter.ToUInt32(target,b+62);
                            if(font>=strings.Count || text>=strings.Count)throw new InvalidDataException("UI_LAYOUT");
                            if(strings[(int)font]!="regular" || strings[(int)text]!="$back")continue;
                            if(target[b+32]!=2 && target[b+32]!=1)throw new InvalidDataException("UI_LAYOUT");
                            int backX=BitConverter.ToInt32(target,b+15);
                            int center=backWidth==0?backX:(backWidth==200?checked((backX+300)/2):checked(backX+200));
                            if(center<300 || center>1024)throw new InvalidDataException("UI_LAYOUT");
                            Buffer.BlockCopy(BitConverter.GetBytes(center-200),0,output,b+15,4);
                            Buffer.BlockCopy(BitConverter.GetBytes(400),0,output,b+23,4);
                            output[b+32]=2;matched++;
                        }
                    }
                }
            }
            if(roots!=1 || matched==0 || chapterMatched!=5)throw new InvalidDataException("UI_LAYOUT");
            return output;
        }
        public static byte[] SpaceDifficultyDescription(byte[] target) {
            byte[] output=(byte[])target.Clone();int matched=0;
            byte[] marker=Utf8.GetBytes("$back\0");
            foreach(int root in UiChunks(target,0,target.Length)) {
                int rootEnd=UiEnd(target,root);bool ui=false;
                for(int p=root+8;p<=rootEnd-marker.Length;p++) {
                    int i=0;while(i<marker.Length && target[p+i]==marker[i])i++;
                    if(i==marker.Length){ui=true;break;}
                }
                if(!ui)continue;
                var fields=UiChunks(target,root+9,rootEnd);
                if(fields.Count!=2)throw new InvalidDataException("DIFFICULTY_LAYOUT");
                int s=fields[1]+8,send=UiEnd(target,fields[1]);uint count=BitConverter.ToUInt32(target,s);s+=4;
                var strings=new List<string>();
                for(uint i=0;i<count;i++) {
                    int begin=s;while(s<send && target[s]!=0)s++;
                    if(s==send)throw new InvalidDataException("DIFFICULTY_LAYOUT");
                    strings.Add(Utf8.GetString(target,begin,s-begin));s++;
                }
                var containers=UiChunks(target,fields[0]+8,UiEnd(target,fields[0]));
                if(containers.Count!=1)throw new InvalidDataException("DIFFICULTY_LAYOUT");
                int ca=containers[0]+8;
                foreach(int screen in UiChunks(target,ca+5,UiEnd(target,containers[0]))) {
                    int a=screen+8;uint name=BitConverter.ToUInt32(target,a+1);
                    if(name>=strings.Count)throw new InvalidDataException("DIFFICULTY_LAYOUT");
                    if(strings[(int)name]!="new_game_step2")continue;
                    foreach(int group in UiChunks(target,a+35,UiEnd(target,screen))) {
                        foreach(int item in UiChunks(target,group+13,UiEnd(target,group))) {
                            int b=item+8;uint itemName=BitConverter.ToUInt32(target,b+5);
                            if(itemName>=strings.Count)throw new InvalidDataException("DIFFICULTY_LAYOUT");
                            if(strings[(int)itemName]!="hint_desc")continue;
                            if(UiEnd(target,item)-b!=86 || BitConverter.ToUInt32(target,b+1)!=9 ||
                               BitConverter.ToInt32(target,b+15)!=23 || BitConverter.ToInt32(target,b+23)!=412)
                                throw new InvalidDataException("DIFFICULTY_LAYOUT");
                            int y=BitConverter.ToInt32(target,b+19),h=BitConverter.ToInt32(target,b+27);
                            if(!((y==194 && h==289)||(y==214 && h==269)))throw new InvalidDataException("DIFFICULTY_LAYOUT");
                            Buffer.BlockCopy(BitConverter.GetBytes(214),0,output,b+19,4);
                            Buffer.BlockCopy(BitConverter.GetBytes(269),0,output,b+27,4);matched++;
                        }
                    }
                }
            }
            if(matched!=1)throw new InvalidDataException("DIFFICULTY_LAYOUT");
            return output;
        }
        const string DlcFontAlias = "ganza_loot_light";

        static List<string> ReadDlcStrings(byte[] data,int start,int end,uint count) {
            if(count>end-start)throw new InvalidDataException("UNSUPPORTED_LAYOUT");
            var strings=new List<string>();
            for(uint i=0;i<count;i++) {
                int zero=Array.IndexOf(data,(byte)0,start,end-start);
                if(zero<0)throw new InvalidDataException("UNSUPPORTED_LAYOUT");
                strings.Add(Utf8.GetString(data,start,zero-start));
                start=zero+1;
            }
            if(start!=end)throw new InvalidDataException("UNSUPPORTED_LAYOUT");
            return strings;
        }

        public static byte[] AddDlcBoardFont(byte[] config) {
            int matches=0;
            using(var result=new MemoryStream())using(var writer=new BinaryWriter(result)) {
                foreach(int chunk in UiChunks(config,0,config.Length)) {
                    int end=UiEnd(config,chunk);
                    if(BitConverter.ToUInt32(config,chunk)!=0xFA8EEA67 ||
                       Encoding.ASCII.GetString(config,chunk+8,end-chunk-8).IndexOf("font\\font_font_regular_us\0",StringComparison.Ordinal)<0) {
                        writer.Write(config,chunk,end-chunk);
                        continue;
                    }
                    matches++;
                    int start=chunk+8;
                    if(end-start<34 || config[start]!=4 || BitConverter.ToUInt32(config,start+1)!=1)
                        throw new InvalidDataException("UNSUPPORTED_LAYOUT");
                    int stringChunk=checked(start+9+(int)BitConverter.ToUInt32(config,start+5));
                    if(stringChunk!=checked(start+17+(int)BitConverter.ToUInt32(config,start+13)) ||
                       stringChunk<start+22 || stringChunk+12>end ||
                       BitConverter.ToUInt32(config,stringChunk)!=2 || UiEnd(config,stringChunk)!=end)
                        throw new InvalidDataException("UNSUPPORTED_LAYOUT");
                    uint count=BitConverter.ToUInt32(config,stringChunk+8);
                    var strings=ReadDlcStrings(config,stringChunk+12,end,count);
                    var records=UiChunks(config,start+22,stringChunk);
                    if(records.Count!=BitConverter.ToUInt32(config,start+18) || strings.Contains(DlcFontAlias))
                        throw new InvalidDataException("UNSUPPORTED_LAYOUT");
                    byte[] clone=null;
                    foreach(int record in records) {
                        int length=UiEnd(config,record)-record;
                        if(length<21)throw new InvalidDataException("UNSUPPORTED_LAYOUT");
                        uint name=BitConverter.ToUInt32(config,record+13),texture=BitConverter.ToUInt32(config,record+17);
                        if(name>=count || texture>=count)throw new InvalidDataException("UNSUPPORTED_LAYOUT");
                        if(strings[(int)name]!="regular")continue;
                        if(clone!=null || strings[(int)texture]!="font\\font_font_regular_us")
                            throw new InvalidDataException("UNSUPPORTED_LAYOUT");
                        clone=new byte[length];Buffer.BlockCopy(config,record,clone,0,length);
                    }
                    if(clone==null)throw new InvalidDataException("UNSUPPORTED_LAYOUT");
                    byte[] extra=Utf8.GetBytes(DlcFontAlias+"\0font\\font_ganza_loot_hu\0");
                    Buffer.BlockCopy(BitConverter.GetBytes(count),0,clone,13,4);
                    Buffer.BlockCopy(BitConverter.GetBytes(count+1),0,clone,17,4);
                    writer.Write(BitConverter.ToUInt32(config,chunk));writer.Write(end-start+clone.Length+extra.Length);
                    writer.Write(config,start,5);
                    writer.Write(BitConverter.ToUInt32(config,start+5)+(uint)clone.Length);
                    writer.Write(config,start+9,4);
                    writer.Write(BitConverter.ToUInt32(config,start+13)+(uint)clone.Length);
                    writer.Write(config[start+17]);writer.Write(records.Count+1);
                    writer.Write(config,start+22,stringChunk-start-22);writer.Write(clone);
                    writer.Write(2u);writer.Write(BitConverter.ToUInt32(config,stringChunk+4)+(uint)extra.Length);
                    writer.Write(count+2);writer.Write(config,stringChunk+12,end-stringChunk-12);writer.Write(extra);
                }
                if(matches!=1)throw new InvalidDataException("UNSUPPORTED_LAYOUT");
                return result.ToArray();
            }
        }

        public static byte[] PatchDlcBoard(byte[] level) {
            if(level.Length<32 || BitConverter.ToUInt32(level,0)!=0x6C76656C ||
               UiEnd(level,0)!=level.Length || level[8]!=0x24)
                throw new InvalidDataException("UNSUPPORTED_LAYOUT");
            int chunk=checked(17+(int)BitConverter.ToUInt32(level,13));
            if(chunk<29 || chunk>level.Length-12 || BitConverter.ToUInt32(level,chunk)!=2 || UiEnd(level,chunk)!=level.Length)
                throw new InvalidDataException("UNSUPPORTED_LAYOUT");
            uint count=BitConverter.ToUInt32(level,chunk+8);
            var strings=ReadDlcStrings(level,chunk+12,level.Length,count);
            int font=strings.IndexOf("regular");
            if(font<0 || strings.Contains(DlcFontAlias))throw new InvalidDataException("UNSUPPORTED_LAYOUT");
            var targets=new HashSet<int>();
            for(int i=1;i<=30;i++) {
                int id=strings.IndexOf("dlc_ranger_loot_dsc_"+i);
                if(id<0)throw new InvalidDataException("UNSUPPORTED_LAYOUT");
                targets.Add(id);
            }
            var bright=new HashSet<int>();var dark=new HashSet<int>();
            byte[] extra=Utf8.GetBytes(DlcFontAlias+"\0");
            byte[] output=new byte[level.Length+extra.Length];
            Buffer.BlockCopy(level,0,output,0,level.Length);
            uint white=0x3F7DFDFF;
            for(int p=29;p+34<=chunk;p++) {
                int id=BitConverter.ToInt32(level,p);
                if(!targets.Contains(id) || BitConverter.ToInt32(level,p+30)!=font)continue;
                uint red=BitConverter.ToUInt32(level,p+10);
                if(BitConverter.ToUInt16(level,p+8)!=0x0100 || BitConverter.ToUInt32(level,p+14)!=red ||
                   BitConverter.ToUInt32(level,p+18)!=red || BitConverter.ToUInt32(level,p+22)!=0x3F800000)
                    throw new InvalidDataException("UNSUPPORTED_LAYOUT");
                if(red==0) {
                    if(!dark.Add(id))throw new InvalidDataException("UNSUPPORTED_LAYOUT");
                } else if(red==white) {
                    if(!bright.Add(id))throw new InvalidDataException("UNSUPPORTED_LAYOUT");
                    Buffer.BlockCopy(BitConverter.GetBytes(count),0,output,p+30,4);
                } else throw new InvalidDataException("UNSUPPORTED_LAYOUT");
            }
            if(!targets.SetEquals(bright) || !targets.SetEquals(dark))throw new InvalidDataException("UNSUPPORTED_LAYOUT");
            Buffer.BlockCopy(extra,0,output,level.Length,extra.Length);
            Buffer.BlockCopy(BitConverter.GetBytes(output.Length-8),0,output,4,4);
            Buffer.BlockCopy(BitConverter.GetBytes(BitConverter.ToUInt32(level,chunk+4)+(uint)extra.Length),0,output,chunk+4,4);
            Buffer.BlockCopy(BitConverter.GetBytes(count+1),0,output,chunk+8,4);
            return output;
        }

        public static byte[] ReplaceEnglishFontSection(byte[] target,byte[] replacement) {
            byte[] marker=Utf8.GetBytes("font\\font_font_regular_us\0");int found=0;var output=new MemoryStream();
            using(var r=new BinaryReader(new MemoryStream(target,false)))using(var w=new BinaryWriter(output)) {
                while(r.BaseStream.Position<target.Length) {
                    uint key=r.ReadUInt32(),size=r.ReadUInt32();if(size>target.Length-r.BaseStream.Position)throw new InvalidDataException("CONFIG_LAYOUT");
                    byte[] body=r.ReadBytes(checked((int)size));bool match=false;
                    for(int i=0;i<=body.Length-marker.Length;i++){int j=0;while(j<marker.Length && body[i+j]==marker[j])j++;if(j==marker.Length){match=true;break;}}
                    if(match){found++;w.Write(key);w.Write(checked((uint)replacement.Length));w.Write(replacement);}else{w.Write(key);w.Write(size);w.Write(body);}
                }
                if(found!=1)throw new InvalidDataException("ENGLISH_FONT_LAYOUT");return output.ToArray();
            }
        }
    }
}

namespace LastLightHu {
 public static class BannerFilter {
  sealed class Pe {
   internal byte[] B;int sections,sectionCount,dirs;
   internal Pe(byte[] b){B=b;Require(b.Length>=256 && U16(0)==0x5a4d);int pe=I32(0x3c);Require(U32(pe)==0x4550 && U16(pe+4)==0x8664);sectionCount=U16(pe+6);int optional=pe+24;Require(U16(optional)==0x20b);dirs=optional+112;sections=optional+U16(pe+20);Require(sectionCount>0 && sectionCount<100);At(sections,sectionCount*40);}
   internal int At(int off,int count){Require(off>=0 && count>=0 && off<=B.Length-count);return off;}
   internal ushort U16(int p){return BitConverter.ToUInt16(B,At(p,2));}
   internal uint U32(int p){return BitConverter.ToUInt32(B,At(p,4));}
   internal int I32(int p){return BitConverter.ToInt32(B,At(p,4));}
   internal int Rva(uint rva,int bytes){for(int n=0;n<sectionCount;n++){int s=sections+n*40;uint va=U32(s+12),size=U32(s+16),raw=U32(s+20);if(rva>=va && (ulong)(rva-va)+(uint)bytes<=size)return At(checked((int)(raw+rva-va)),bytes);}throw new InvalidDataException("BANNER_LAYOUT");}
   string Str(uint rva){int p=Rva(rva,1),end=p;while(end<B.Length && B[end]!=0 && end-p<512)end++;Require(end<B.Length && end-p<512);return Encoding.ASCII.GetString(B,p,end-p);}
   internal uint Export(string name){uint er=U32(dirs),sz=U32(dirs+4);int e=Rva(er,40);uint count=U32(e+24),functions=U32(e+28),names=U32(e+32),ordinals=U32(e+36);Require(count<100000);for(uint n=0;n<count;n++){uint nr=U32(Rva(names+n*4,4));if(Str(nr)!=name)continue;ushort ordinal=U16(Rva(ordinals+n*2,2));uint fn=U32(Rva(functions+(uint)ordinal*4,4));Require(fn<er || fn>=er+sz);return fn;}throw new InvalidDataException("BANNER_LAYOUT");}
   internal int[] Function(uint rva){uint dir=U32(dirs+3*8),size=U32(dirs+3*8+4);Require(size>0 && size%12==0);int p=Rva(dir,checked((int)size));for(int i=0;i<size;i+=12){uint begin=U32(p+i),end=U32(p+i+4);if(begin==rva){Require(end>begin && end-begin<=8192);return new[]{Rva(begin,checked((int)(end-begin))),checked((int)(end-begin))};}}throw new InvalidDataException("BANNER_LAYOUT");}
  }
  static void Require(bool ok){if(!ok)throw new InvalidDataException("BANNER_LAYOUT");}
  static int Find(byte[] b,int start,int length,byte[] pattern){int found=-1;for(int p=start;p<=start+length-pattern.Length;p++){int i=0;while(i<pattern.Length && (pattern[i]==0xff || b[p+i]==pattern[i]))i++;if(i!=pattern.Length)continue;Require(found<0);found=p;}Require(found>=0);return found;}
  public static int[] Offsets(byte[] data){
   var pe=new Pe(data);uint cached=pe.Export("prosdk_banner_get_banner_spaces_from_cache");pe.Export("prosdk_banner_get_banner_spaces");pe.Export("prosdk_banner_get_banner_spaces_result_release");
   int[] f=pe.Function(cached);
   // Locate the native result converter through the cache export's call.
   byte[] call={0x48,0x8d,0x54,0x24,0x20,0x48,0x8b,0xcb,0xe8,0xff,0xff,0xff,0xff};int c=Find(data,f[0],f[1],call);int disp=pe.I32(c+9);uint convert=checked((uint)((long)cached+c-f[0]+13+disp));int[] cv=pe.Function(convert);
   // Both branches already have native empty-array paths. Suppress only
   // their non-empty alternatives; metadata and native callback flow stay.
   byte[] first={0x48,0x8b,0x4a,0x10,0x48,0x8b,0x42,0x18,0x48,0x3b,0xc8,0xff,0xff,0x33,0xf6,0x49,0x89,0x75,0x18,0x49,0x89,0x75,0x10,0xe9};
   byte[] second={0x49,0x8b,0x4c,0x24,0x28,0x49,0x8b,0x44,0x24,0x30,0x48,0x3b,0xc8,0xff,0xff,0x49,0x89,0x75,0x28,0x49,0x89,0x75,0x20,0xe9};
   int a=Find(data,cv[0],cv[1],first)+11,b=Find(data,cv[0],cv[1],second)+13;
   bool original=data[a]==0x75 && data[a+1]==0x0f && data[b]==0x75 && data[b+1]==0x0d;
   bool filtered=data[a]==0x90 && data[a+1]==0x90 && data[b]==0x90 && data[b+1]==0x90;
   Require(original || filtered);return new[]{a,a+1,b,b+1};
  }
  static int InitializationGate(byte[] data) {
   var pe=new Pe(data);int[] f=pe.Function(pe.Export("prosdk_init"));
   // Keep the SDK's existing prologue, native early-error return (108), and
   // epilogue. Suppress only the version-success branch into initialization.
   byte[] pattern={0x41,0x81,0xf8,0xff,0xff,0xff,0xff,0xff,0xff,0xb8,0x6c,0,0,0,0x48,0x81,0xc4,0xff,0xff,0xff,0xff,0x5e,0x5b,0x5d,0xc3};
   int p=Find(data,f[0],Math.Min(f[1],128),pattern)+7;
   Require((data[p]==0x74 && data[p+1]==0x10)||(data[p]==0x90 && data[p+1]==0x90));
   return p;
  }
  public static string Inspect(byte[] data){
   int[] offsets=Offsets(data);int gate=InitializationGate(data);
   bool legacy=data[offsets[0]]==0x90,disabled=data[gate]==0x90;
   Require(!(legacy && disabled));
   return legacy || disabled?"FILTERED":"ORIGINAL";
  }
  public static byte[] Apply(byte[] data){
   Inspect(data);int[] offsets=Offsets(data);int gate=InitializationGate(data);
   byte[] result=(byte[])data.Clone();
   // Migrate a recognized 0.1.5 filter, without retaining its vector patches.
   byte[] native={0x75,0x0f,0x75,0x0d};
   for(int i=0;i<offsets.Length;i++)result[offsets[i]]=native[i];
   result[gate]=0x90;result[gate+1]=0x90;return result;
  }
 }
}
