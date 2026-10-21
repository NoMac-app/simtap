// Sets or prints the Simulator's own pasteboard from inside the phone (simctl spawn), without the host's pasteboard,
// which a user with no screen session does not have. pbset TEXT sets it; pbset with no argument prints it.
#import <UIKit/UIKit.h>
int main(int argc, char *argv[]) {
  @autoreleasepool {
    UIPasteboard *pb = [UIPasteboard generalPasteboard];
    long before = (long)pb.changeCount;
    if (argc > 1) {
      [pb setItems:@[@{@"public.utf8-plain-text": [NSString stringWithUTF8String:argv[1]]}] options:@{}];
      // The pasteboard server takes the write asynchronously: give it a moment before the process exits.
      [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
      fprintf(stderr, "changeCount %ld -> %ld, hasStrings %d\n", before, (long)pb.changeCount, pb.hasStrings);
    } else {
      fprintf(stderr, "changeCount %ld, hasStrings %d\n", before, pb.hasStrings);
      printf("%s\n", (pb.string ?: @"").UTF8String);
    }
  }
  return 0;
}
