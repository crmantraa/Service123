@isTest
public class SRV_CaseHandler_Test {
    
    @testSetup 
    static void DefaultCaseValues_Service()
    {
        SRV_Notification_Config__c NotifConfig = TestUtil.NotificationCustomSetting('To Do','Education_To','SRV_Case_Created1','Case','ContactEmail','Account_Owner__c');
        SRV_Notification_Config__c notifconfigCEM = TestUtil.NotificationCustomSetting('Customer Event Management','Education','SRV_Case_Comment','Time Log','Case_Contact_Email__c','');
        SRV_Notification_Config__c notifconfigCEM1 = TestUtil.NotificationCustomSetting('Internal Event Management','Education','SRV_Case_Comment','Time Log','Case_Contact_Email__c','test@test.com');
        
        
        Account Acc = TestUtil.createAccount(true, 'Business');
        Contact con = TestUtil.createContact(Acc.Id, true, 'Contact');
        QueuesObject Qu = TestUtil.CreateQueue('BTS');
        Case cs = TestUtil.CreateServiceCase(Acc.ID, con.id, false, 'Incident');
        cs.OwnerID = Qu.queueId;
        cs.status = 'To Do';
        insert cs;
    }
     static testmethod void ClosedCase()
    {
        Case cs = [SELECT Id FROM Case LIMIT 1];   
        cs.OwnerId = UserInfo.getUserId();
        cs.status = 'Resolved / Monitor';
        //cs.RFO_Description__c = 'TEst description';
        cs.Reason_for_Outage__c = 'Hardware';
        //cs.Latest_Case_Status__c = 'TEst case status';
        update cs;
        
        TestUtil.CreateServSett();
        TestUtil.createServiceTimecard(true,cs.Id,'RFO Description');
        SRV_Notification_Config__c NotifConfig = TestUtil.NotificationCustomSetting('Closed','Education_To','SRV_Case_Created1','Case','ContactEmail','Account_Owner__c');
        cs.Status = 'Closed';
        update cs; 
    }
    
    static testmethod void CreateRecurringCasesTest()
    {
        Case cs = [SELECT Id FROM Case LIMIT 1];
        cs.status = 'To Do';
        cs.Recurrence__c = true;
        cs.Start_Date__c = system.today();
        cs.End_Date__c = system.today().addDays(2);
        cs.Frequency__c = 'Daily';
        cs.OwnerId = UserInfo.getUserId();
        update cs;
        
        cs.Frequency__c = 'Yearly';
        cs.status = 'In Progress';
        cs.Notification_Lists__c = 'test@test.com';
        update cs;
        
        cs.Frequency__c = 'Monthly';
        update cs;
        
        cs.Frequency__c = 'Weekly';
        update cs;
        
        cs.Frequency__c = 'Daily';
        update cs;
    }
    
    static testmethod void CreateCaseComment_Test()
    {
        Case cs = [SELECT Id FROM Case LIMIT 1];
        
        ServiceSettings__c svSettings = TestUtil.CreateServSett();
        cs.OwnerId = UserInfo.getUserId();
        update cs;
        
         SRV_Notification_Config__c NotifConfig = TestUtil.NotificationCustomSetting('To Do','Education_To','SRV_Case_Created1','Case','ContactEmail','Account_Owner__c');
        SRV_caseHandler.SendErrNotification('Error while creating Case comment');
        SFDC_Service_Timecard__c TimeLog = TestUtil.createServiceTimecard(true,cs.Id,'Case Work');
        CaseComment  cc = new casecomment();
        cc.IsPublished = true;
        cc.CommentBody = 'TEst';
        cc.ParentId = cs.id;
        insert cc;
        list<casecomment> lstcomm = new list<casecomment>();
        lstcomm.add(cc);
        SRV_caseHandler.PrependTechNameOnCaseComment(lstcomm);
        SRV_CaseHandler.getThreadId(cs.id);
    }
    
    static testmethod void EmailMessage_Test()
    {
        Case cs = [SELECT Id FROM Case LIMIT 1];
        cs.OwnerId = UserInfo.getUserId();
        update cs;
        EmailMessage Em = TestUtil.CreateEmailMessage(true,cs.Id);
        //em.Incoming = false;
        //update em;
    } 
    
    static testmethod void CreateActivityonCase_Test()
    {
        Case cs = [SELECT Id FROM Case LIMIT 1];
        cs.OwnerId = UserInfo.getUserId();
        update cs;
        TestUtil.CreateServSett();
        SFDC_Service_Timecard__c timLog= TestUtil.createServiceTimecard(true,cs.Id,'Internal Event Management');
        list<SFDC_Service_Timecard__c> lstTimeLog = new list<SFDC_Service_Timecard__c>();
        lstTimeLog.add(timLog);
         SRV_Notification_Config__c NotifConfig = TestUtil.NotificationCustomSetting('To Do','Education_To','SRV_Case_Created1','Case','ContactEmail','Account_Owner__c');
        EmailMessage Em = TestUtil.CreateEmailMessage(false,cs.Id);
        em.RelatedToId = timLog.Id;
        em.Incoming = false;
        insert em;
        list<Emailmessage> Lstem= new list<EmailMEssage>();
        SRV_CaseHandler.CreateActivityonCase(Lstem);
        SRV_CaseHandler.SendTimeLogNotification(lstTimeLog);
    } 
    
    static testmethod void CaseCreatedEducationNotification()
    {
        //NotificationCustomSetting(string name,string strmarketSeg,string TemplateName,string objName,string recipients)
       
        Case cs = [SELECT Id FROM Case LIMIT 1];
        cs.OwnerId = UserInfo.getUserId();
        update cs;
        SRV_Notification_Config__c notifconfigIEM = TestUtil.NotificationCustomSetting('Internal Event Management','Education','SRV_Case_Comment_Internal','Time Log','Account_Owner__c','ContactEmail__c');
        SFDC_Service_Timecard__c TimeLog = TestUtil.createServiceTimecard(true,cs.Id,'Internal Event Management');
    }
    
        static testmethod void CreateSvcEvt()
          { 
                     Account Accnt = [Select Id,Name,vlocity_cmt__Status__c,RecordTypeId,RecordType.Name
                                           FROM Account WHERE vlocity_cmt__Status__c = 'Active' and RecordType.Name = 'Business' LIMIT 1];
                     ID Acctid = Accnt.Id;
                     RecordType Rt = [SELECT id,Name FROM RecordType WHERE  Name =  'Alert/Event' AND DeveloperName Like 'SRV%'];
        
                    if (Rt.Name == 'Alert/Event')
                      {
                            ID RTid = Rt.id;
                            Case cs = [SELECT Id FROM Case LIMIT 1];  
                            cs.Subject = 'Test Case for Service record Types';
                            Cs.Description = 'Test for Alert/Event and Incident type Record';
                            cs.Origin =  'Phone';
                            cs.Product_Service__c  = 'Cloud Services';
                            cs.Business_Impact__c = 'Support';
                            cs.Priority = 'P1  - Critical';
                            cs.Status =   'In Progress';       
                            cs.SRV_Support_Team__c  = 'BTS';
                            cs.AccountId  =  Acctid;
                            cs.RecordTypeId = RTid;
                            update cs;
          
                            SRV_Service_Event__c  svcevnt = new SRV_Service_Event__c();
                            svcevnt.Case__c  = cs.id;
                            svcevnt.Event_Start__c = cs.CreatedDate;
                            insert svcevnt; 
                     }
        
           }
}