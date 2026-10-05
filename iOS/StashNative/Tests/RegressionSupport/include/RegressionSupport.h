#import <Foundation/Foundation.h>
NSDictionary *AuditSynchronous(void);
void AuditRetention(void (^completion)(BOOL));
void AuditSafariThread(void (^completion)(BOOL, NSInteger));
BOOL AuditDismissResetReopen(void);
void AuditQueuedClose(BOOL replace, BOOL startProcessing, void (^completion)(BOOL, NSInteger));
NSDictionary *RegressionURLs(void);
BOOL RegressionAccessibility(void);
